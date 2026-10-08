###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
###

class TeamCurrentTasksController
    @.$inject = ["$scope", "$q", "tgProjectService", "tgResources", "$tgAuth",
                 "$tgHttp", "$tgUrls", "$tgNavUrls", "tgAppMetaService", "$translate"]

    constructor: (@scope, @q, @projectService, @resources, @auth, @http, @urls, @nav, @meta, @translate) ->
        @project = @projectService.project.toJS()
        @scope.project = @project
        @scope.$emit("project:loaded", @project)
        @filters = {query: "", project: "", role: "", status: "", sprint: ""}
        @members = (member for member in @project.members when member.is_active)
        @roles = @project.roles
        @rows = []
        @projects = []
        @statuses = []
        @sprints = []
        @summary = {members: @members.length, progress: 0, blocked: 0, completed: 0}
        @meta.setAll(@translate.instant("TEAM.CURRENT_TASKS.TITLE"), @project.name)
        @load()

    load: ->
        @loading = true
        @error = false
        user = @auth.getUser()
        projectList = if user then @resources.projects.getListProjectsByUserId(user.id) else
            @q.when({toJS: => [@project]})
        projectList.then (projects) =>
            projects = projects.toJS()
            projects.push(@project) unless projects.some((project) => project.id == @project.id)
            @q.all(projects.map((project) => @loadProject(project)))
        .then (results) =>
            @projects = results.map((result) -> result.project)
            @rows = [].concat.apply([], results.map((result) -> result.rows))
            for member in @members
                continue if @rows.some((row) -> row.member.id == member.id)
                role = _.find(@project.roles, {id: member.role})
                @rows.push({
                    key: "idle-#{member.id}", member: member, role: role?.name or "",
                    project: @project, item: {}, status: @translate.instant("TEAM.CURRENT_TASKS.IDLE"),
                    state: "idle", sprintKey: ""
                })
            @statuses = _.uniq(@rows.map((row) -> row.status)).sort()
            @sprints = [].concat.apply([], results.map((result) -> result.sprints))
            @applyFilters()
        .catch =>
            @error = true
            @rows = []
            @visibleRows = []
        .finally => @loading = false

    loadProject: (summary) ->
        detail = if summary.id == @project.id then @q.when(@project) else
            @resources.projects.getProjectStats(summary.id).then((project) -> project.toJS())
        detail.then (project) =>
            requests = []
            if project.is_backlog_activated or project.is_kanban_activated
                requests.push(@resources.tasks.listInAllProjects({project: project.id})
                    .then((items) -> {type: "task", items: items.toJS()}))
                requests.push(@resources.userstories.listInAllProjects({project: project.id})
                    .then((items) -> {type: "userstory", items: items.toJS()}))
            sprints = @q.when([])
            if project.is_backlog_activated
                sprints = @http.get(@urls.resolve("milestones"), {project: project.id},
                    {headers: {"x-disable-pagination": "1"}}).then((response) -> response.data)
            @q.all([@q.all(requests), sprints]).then ([groups, milestones]) =>
                rows = []
                for group in groups
                    for item in group.items
                        member = _.find(@members, {id: item.assigned_to})
                        continue unless member
                        statusList = if group.type == "task" then project.task_statuses else project.us_statuses
                        status = item.status_extra_info or _.find(statusList, {id: item.status}) or {}
                        closed = item.is_closed or status.is_closed
                        completedToday = closed and item.finished_date and
                            moment(item.finished_date).isSame(moment(), "day")
                        continue if closed and not completedToday
                        role = _.find(project.roles, {id: _.find(project.members, {id: member.id})?.role})
                        sprint = _.find(milestones, {id: item.milestone})
                        state = if item.is_blocked then "blocked" else if closed then "completed" else
                            if /progress|doing|working/i.test(status.name or "") then "progress" else "other"
                        route = if group.type == "task" then "project-tasks-detail" else "project-userstories-detail"
                        rows.push({
                            key: "#{group.type}-#{item.id}", member: member,
                            role: role?.name or "", project: project, item: item,
                            type: group.type, status: status.name or "—", state: state,
                            completedToday: !!completedToday, sprint: sprint,
                            sprintKey: if sprint then "#{project.id}-#{sprint.id}" else "",
                            url: @nav.resolve(route, {project: project.slug, ref: item.ref})
                        })
                return {project: project, rows: rows, sprints: milestones.map((sprint) ->
                    {key: "#{project.id}-#{sprint.id}", name: "#{project.name} · #{sprint.name}"})}

    applyFilters: ->
        query = @filters.query.toLowerCase().trim()
        base = @rows.filter (row) =>
            name = row.member.full_name_display or row.member.full_name or row.member.username or ""
            matchesRole = not @filters.role or String(row.member.role) == String(@filters.role)
            return (not query or name.toLowerCase().indexOf(query) != -1) and matchesRole and
                (not @filters.project or String(row.project.id) == String(@filters.project)) and
                (not @filters.sprint or row.sprintKey == @filters.sprint)
        @summary = {
            members: @members.filter((member) =>
                name = member.full_name_display or member.full_name or member.username or ""
                (not query or name.toLowerCase().indexOf(query) != -1) and
                    (not @filters.role or String(member.role) == String(@filters.role))).length,
            progress: base.filter((row) -> row.state == "progress").length,
            blocked: base.filter((row) -> row.state == "blocked").length,
            completed: base.filter((row) -> row.completedToday).length
        }
        @visibleRows = _.sortBy(base.filter((row) => not @filters.status or row.status == @filters.status),
            (row) -> row.member.full_name_display or row.member.username)

angular.module("taigaTeam").controller("TeamCurrentTasksController", TeamCurrentTasksController)
