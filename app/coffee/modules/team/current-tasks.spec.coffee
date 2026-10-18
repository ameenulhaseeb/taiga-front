describe "Native team current tasks dashboard", ->
    controller = root = q = interval = http = requests = vm = null
    payload = -> {
        stats: {members: 3, progress: 2, blocked: 1, completed: 0},
        totalAssignments: 2, displayedMembers: 3, timezone: "Asia/Kolkata",
        generatedAt: "2026-10-18T09:00:00Z",
        options: {
            projects: [{id: "1", name: "RPP"}], teamLeads: [{id: "9", name: "Lead"}],
            roles: ["Developer"], sprints: []
        },
        rows: [
            {key: "task-1-10", type: "Task", ref: 1, projectSlug: "rpp", memberName: "Faris K", state: "progress"},
            {key: "task-2-10", type: "Task", ref: 2, projectSlug: "rpp", memberName: "Faris K", state: "progress"},
            {key: "idle-11", memberName: "Other Member", state: "idle"}
        ]
    }
    beforeEach ->
        module "taigaTeam"
        inject ($controller, $rootScope, $q, $interval) ->
            controller = $controller
            root = $rootScope
            q = $q
            interval = $interval
        requests = []
        http = {
            get: (url, params) ->
                request = {url: url, params: angular.copy(params), deferred: q.defer()}
                requests.push(request)
                return request.deferred.promise
        }
        vm = controller "TeamCurrentTasksController", {
            $scope: root.$new(), $interval: interval,
            tgProjectService: {project: Immutable.fromJS({id: 1, slug: "rpp", name: "RPP"})},
            $tgHttp: http, $tgUrls: {resolve: (key, id) -> "/projects/#{id}/current_tasks"},
            $tgNavUrls: {resolve: (route, p) -> "/#{p.project}/#{route}/#{p.ref}"},
            tgAppMetaService: {setAll: ->}, $translate: {instant: (key) -> key}
        }
    finish = (index=0, value=payload()) ->
        requests[index].deferred.resolve({data: value})
        root.$digest()

    it "requests all in-progress assignments by default", ->
        expect(requests[0].params.view).to.equal("all")
        expect(requests[0].params.status).to.equal("progress")
        finish()
        expect(vm.visibleRows.length).to.equal(3)
        expect(vm.totalAssignments).to.equal(2)
        expect(vm.visibleRows[2].url).to.equal(undefined)
        expect(vm.visibleRows[0].initials).to.equal("FK")

    it "sends the lead and resets dependent filters", ->
        vm.filters.teamLead = "9"
        vm.filters.project = "2"
        vm.filters.role = "QA"
        vm.filters.sprint = "4"
        vm.leadChanged()
        expect(requests[1].params.teamLead).to.equal("9")
        expect(requests[1].params.project).to.equal("")
        expect(requests[1].params.role).to.equal("")
        expect(requests[1].params.sprint).to.equal("")

    it "clears filters while keeping the all-assignment view", ->
        vm.clearFilters()
        expect(requests[1].params.status).to.equal("")
        expect(requests[1].params.view).to.equal("all")

    it "ignores stale responses", ->
        vm.load()
        newer = payload()
        newer.totalAssignments = 50
        finish(1, newer)
        finish(0)
        expect(vm.totalAssignments).to.equal(50)

    it "shows an error without stale rows and supports retry", ->
        requests[0].deferred.reject({status: 503})
        root.$digest()
        expect(vm.error).to.equal(true)
        expect(vm.visibleRows.length).to.equal(0)
        vm.load()
        finish(1)
        expect(vm.error).to.equal(false)
        expect(vm.summary.progress).to.equal(2)

    it "resolves issue and user story links through native routes", ->
        value = payload()
        value.rows[0].type = "Issue"
        value.rows[1].type = "User Story"
        finish(0, value)
        expect(vm.visibleRows[0].url).to.equal("/rpp/project-issues-detail/1")
        expect(vm.visibleRows[1].url).to.equal("/rpp/project-userstories-detail/2")

    it "cancels auto refresh and ignores late responses when destroyed", ->
        vm.scope.$destroy()
        finish()
        expect(vm.visibleRows.length).to.equal(0)
        interval.flush(60000)
        expect(requests.length).to.equal(1)
