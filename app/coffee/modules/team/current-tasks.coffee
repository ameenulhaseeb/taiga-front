###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
###

class TeamCurrentTasksController
    @.$inject = ["$scope", "$interval", "tgProjectService", "$tgHttp", "$tgUrls",
                 "$tgNavUrls", "tgAppMetaService", "$translate"]

    constructor: (@scope, @interval, @projectService, @http, @urls, @nav, @meta, @translate) ->
        @project = @projectService.project.toJS()
        @scope.project = @project
        @scope.$emit("project:loaded", @project)
        @filters = {query: "", teamLead: "", project: "", role: "", status: "progress", sprint: "", type: ""}
        @visibleRows = []
        @projects = @roles = @teamLeads = @sprints = []
        @summary = {members: 0, progress: 0, blocked: 0, completed: 0}
        @totalAssignments = @displayedMembers = @sequence = 0
        @meta.setAll(@translate.instant("TEAM.CURRENT_TASKS.TITLE"), @project.name)
        timer = @interval((=> @load() unless @loading or document.hidden), 30000)
        @scope.$on "$destroy", =>
            @destroyed = true
            @sequence += 1
            @interval.cancel(timer)
        @load()

    load: ->
        sequence = ++@sequence
        @loading = true
        @error = false
        params = {
            q: @filters.query, teamLead: @filters.teamLead, project: @filters.project,
            role: @filters.role, status: @filters.status, sprint: @filters.sprint,
            type: @filters.type, view: "all"
        }
        @http.get(@urls.resolve("project-current-tasks", @project.id), params).then (response) =>
            return if @destroyed or sequence != @sequence
            data = response.data
            @summary = data.stats
            @projects = data.options.projects
            @teamLeads = data.options.teamLeads
            @roles = data.options.roles
            @sprints = data.options.sprints
            @totalAssignments = data.totalAssignments
            @displayedMembers = data.displayedMembers
            @generatedAt = data.generatedAt
            @timezone = data.timezone
            @visibleRows = data.rows.map (row) =>
                if row.state != "idle"
                    route = if row.type == "Task" then "project-tasks-detail" else
                        if row.type == "Issue" then "project-issues-detail" else "project-userstories-detail"
                    row.url = @nav.resolve(route, {project: row.projectSlug, ref: row.ref})
                row.initials = row.memberName.trim().split(/\s+/).slice(0, 2).map((part) -> part[0]).join("").toUpperCase()
                return row
        .catch =>
            return if @destroyed or sequence != @sequence
            @error = true
            @visibleRows = []
            @totalAssignments = @displayedMembers = 0
            @summary = {members: 0, progress: 0, blocked: 0, completed: 0}
        .finally =>
            @loading = false if sequence == @sequence

    leadChanged: ->
        @filters.project = @filters.role = @filters.sprint = ""
        @load()

    projectChanged: ->
        @filters.sprint = ""
        @load()

    clearFilters: ->
        @filters = {query: "", teamLead: "", project: "", role: "", status: "", sprint: "", type: ""}
        @load()

    filterStatus: (status) ->
        @filters.status = status
        @load()

angular.module("taigaTeam").controller("TeamCurrentTasksController", TeamCurrentTasksController)

# Keep initials visible underneath a missing or inaccessible profile image.
angular.module("taigaTeam").directive "tgCurrentTasksPhoto", ->
    restrict: "A"
    link: (scope, element) ->
        failed = -> element.css("display", "none")
        element.on("error", failed)
        scope.$on "$destroy", -> element.off("error", failed)
