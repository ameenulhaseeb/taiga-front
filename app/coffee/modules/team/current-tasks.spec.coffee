###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
###

describe "Team current tasks dashboard", ->
    controller = root = q = project = tasks = stories = resources = null

    beforeEach ->
        module "taigaTeam"
        inject ($controller, $rootScope, $q) ->
            controller = $controller
            root = $rootScope
            q = $q
        project = {
            id: 1, slug: "rpp", name: "RPP", is_backlog_activated: true,
            members: [
                {id: 10, is_active: true, role: 1, full_name_display: "Faris K"},
                {id: 11, is_active: true, role: 2, full_name_display: "Sreelakshmi"},
                {id: 12, is_active: false, role: 1, full_name_display: "Inactive"}
            ],
            roles: [{id: 1, name: "Backend Developer"}, {id: 2, name: "Frontend Developer"}],
            task_statuses: [{id: 1, name: "In Progress"}, {id: 2, name: "Done", is_closed: true}],
            us_statuses: [{id: 3, name: "Ready"}]
        }
        tasks = [
            {id: 1, assigned_to: 10, subject: "Implement API", ref: 1234, status: 1, milestone: 4},
            {id: 2, assigned_to: 10, subject: "Blocked task", ref: 1235, status: 1, is_blocked: true},
            {id: 3, assigned_to: 10, ref: 1236, status: 2, finished_date: moment().format()},
            {id: 4, assigned_to: 10, ref: 1237, status: 2, finished_date: moment().subtract(1, "day").format()},
            {id: 5, assigned_to: 12, ref: 1238, status: 1},
            {id: 6, assigned_to: null, ref: 1239, status: 1}
        ]
        stories = [{id: 1, assigned_to: 10, ref: 1240, subject: "Plan summary", status: 3}]
        resources = {
            projects: {
                getListProjectsByUserId: -> q.when(Immutable.fromJS([{id: 1}]))
            },
            tasks: {listInAllProjects: -> q.when(Immutable.fromJS(tasks))},
            userstories: {listInAllProjects: -> q.when(Immutable.fromJS(stories))}
        }

    create = (user={id: 10}) ->
        vm = controller "TeamCurrentTasksController", {
            $scope: root.$new(), $q: q,
            tgProjectService: {project: Immutable.fromJS(project)}, tgResources: resources,
            $tgAuth: {getUser: -> user},
            $tgHttp: {get: -> q.when({data: [{id: 4, name: "Sprint 4"}]})},
            $tgUrls: {resolve: -> "/milestones"},
            $tgNavUrls: {resolve: (route, params) -> "/#{params.project}/#{route}/#{params.ref}"},
            tgAppMetaService: {setAll: ->}, $translate: {instant: (key) -> key}
        }
        root.$digest()
        return vm

    it "counts live assignments, excludes inactive/unassigned users and old completions", ->
        vm = create()
        expect(vm.loading).to.equal(false)
        expect(vm.error).to.equal(false)
        expect(vm.summary).to.deep.equal({members: 2, progress: 1, blocked: 1, completed: 1})
        expect(vm.rows.length).to.equal(5)
        expect(vm.rows.map((row) -> row.key)).to.include("idle-11")
        expect(vm.rows.map((row) -> row.key)).not.to.include("task-4")
        expect(vm.rows.map((row) -> row.key)).to.include("userstory-1")

    it "combines member search, role, sprint, project and status filters", ->
        vm = create()
        vm.filters = {query: "  faris ", role: 1, project: 1, sprint: "1-4", status: "In Progress"}
        vm.applyFilters()
        expect(vm.visibleRows.length).to.equal(1)
        expect(vm.visibleRows[0].item.id).to.equal(1)
        vm.filters.query = "missing"
        vm.applyFilters()
        expect(vm.visibleRows.length).to.equal(0)

    it "keeps task and story IDs distinct and resolves native detail links", ->
        vm = create()
        row = _.find(vm.rows, {key: "userstory-1"})
        expect(row.url).to.equal("/rpp/project-userstories-detail/1240")
        expect(_.find(vm.rows, {key: "task-1"}).sprint.name).to.equal("Sprint 4")

    it "shows an error instead of partial data and supports retry", ->
        resources.tasks.listInAllProjects = -> q.reject({status: 403})
        vm = create()
        expect(vm.error).to.equal(true)
        expect(vm.visibleRows.length).to.equal(0)
        resources.tasks.listInAllProjects = -> q.when(Immutable.fromJS(tasks))
        vm.load()
        root.$digest()
        expect(vm.error).to.equal(false)
        expect(vm.summary.blocked).to.equal(1)

    it "supports a public project's anonymous visitors", ->
        vm = create(null)
        expect(vm.error).to.equal(false)
        expect(vm.projects.length).to.equal(1)

    it "includes the same team's assignments in other projects", ->
        other = angular.copy(project)
        other.id = 2
        other.slug = "rem"
        other.name = "REM"
        other.members[0].role = 2
        resources.projects.getListProjectsByUserId = -> q.when(Immutable.fromJS([{id: 1}, {id: 2}]))
        resources.projects.getProjectStats = -> q.when(Immutable.fromJS(other))
        resources.tasks.listInAllProjects = (params) ->
            if params.project == 2
                return q.when(Immutable.fromJS([{id: 100, ref: 100, assigned_to: 10, status: 1}]))
            return q.when(Immutable.fromJS(tasks))
        vm = create()
        row = _.find(vm.rows, {key: "task-100"})
        expect(row.project.name).to.equal("REM")
        expect(row.role).to.equal("Frontend Developer")
        vm.filters.project = 2
        vm.applyFilters()
        expect(vm.visibleRows.length).to.equal(2)
