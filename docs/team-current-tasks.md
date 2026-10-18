# Team Current Tasks dashboard

This feature is integrated into the existing AngularJS/CoffeeScript frontend and Django/PostgreSQL backend. Deploy both repositories from the `feature/team-standup-dashboard` branch together. It needs no separate Node dashboard server, database credentials in the frontend, new database tables, or migrations.

## Open the page

In a project, open **Team**, then **Team – Current Tasks**, or visit:

```
/project/<project-slug>/team/current-tasks
```

## Behavior

- Default: all **In Progress** assignments, one row per assignment; members may appear more than once.
- Members with no matching in-progress work appear last as **No current assignment**, alphabetically within each group. They may have blocked, testing or other work; use Status to see it. Idle rows are omitted for sprint or item-type filters.
- **Team Lead** lists active memberships whose role name is Product Owner (ignoring case and surrounding spaces). Selecting a lead scopes projects and all members' tasks to that lead's projects. Changing the lead clears Project, Role and Sprint.
- Stakeholder / Stakeholders memberships are excluded in every view. A person remains visible in another project where they have a working role.
- Search, Project, Role, Status and Sprint filters combine. Clear filters shows all eligible statuses while retaining all assignment rows.
- User stories assigned to several members appear once per assignee and count once in assignment totals and cards.
- Photos come from Taiga's existing user photo/media storage; initials remain if a photo is unavailable. No extra media configuration is required.
- Unfinished work due before the current dashboard day has a red row and Overdue label. Due today and completed work are excluded from alerts.
- Counts reflect project/member/sprint/type scope. Status affects rows; cards retain other status totals within that scope.
- Native links open task, issue or user-story detail pages. Refresh runs every 30 seconds; the timer stops when leaving the page. Errors display a retry state, not sample data.
- Priority is populated only for issues, because standard tasks and user stories have no priority field.

## Access and scope

The backend uses existing Taiga authentication and permissions. Signed-in users see their accessible membership projects plus the current permitted project; anonymous visitors can only see the current project when existing anonymous permissions allow it. `view_project` is required and each item's `view_tasks`, `view_us` or `view_issues` permission is checked separately. Sprint metadata requires `view_milestones`. Archived projects are excluded. Team Lead is a filter, not an access grant. Private projects are not made public.

## Backend

Read-only endpoint:

```
GET /api/v1/projects/<project-id>/current_tasks
```

Query parameters: `q`, `teamLead`, `project`, `role`, `status`, `sprint`, `type`, `view`.

`status` defaults to `progress`; pass an empty string for all statuses. Allowed states: progress, testing, todo, blocked, completed. `view` defaults to `all`; `current` is available for API consumers. `type` accepts Task, User Story, Issue or empty. Unknown/invalid filters return 400. Results use `Cache-Control: no-store`. Standard read throttles apply. Project data is never writable through this endpoint.

Optional setting in the backend's existing `settings/config.py`:

```python
TEAM_CURRENT_TASKS_TIMEZONE = "Asia/Kolkata"
```

Without it, the backend's `TIME_ZONE` is used for completion and overdue calculations. Ensure this is a valid IANA timezone. Existing `MEDIA_URL`/storage settings control photo URLs.

Use the repository's existing installation and deployment procedure. For local development, after configuring PostgreSQL and installing Taiga's dependencies:

```bash
# taiga-back
python manage.py runserver 0.0.0.0:8000

# taiga-front (in a second terminal; use the Node version supported by this legacy app)
npm install --legacy-peer-deps
npm start
```

Point the frontend's `conf/conf.example.json` API URL to the backend, e.g. `http://localhost:8000/api/v1/`. On PowerShell use `npm.cmd` if execution policy blocks `npm.ps1`. This is the actual Taiga application, so the standalone dashboard's `.env`, port 3000, and Dockerfile are not used. Existing Taiga Docker deployments must rebuild both their frontend and backend images from these source branches; rebuilding only one side is insufficient.

## Validation

Backend logic tests (no Django/database required):

```bash
python -m unittest discover -s tests/unit -p test_current_tasks_data.py -v
```

Native integration tests (requires the project's test dependencies and test PostgreSQL configuration):

```bash
pytest tests/integration/test_current_tasks.py
```

Frontend tests are in `app/coffee/modules/team/current-tasks.spec.coffee` and run with the existing Karma suite. They cover default all-row requests, lead filters, clearing, stale responses, retry, native links and timer cleanup. CoffeeScript/Jade and SCSS compilation and a mocked API/template browser check are also part of the implementation validation. See the pull requests for the checks actually run and remaining deployment checks.

## Source locations

Frontend: `app/coffee/modules/team/current-tasks.coffee`, its `.spec.coffee`, `app/partials/team/current-tasks.jade`, `app/styles/layout/team-current-tasks.scss`, route/resource/nav registrations and locale strings.

Backend: `taiga/projects/current_tasks.py` (authorized ORM adapter), `taiga/projects/current_tasks_data.py` (filtering and projection), ProjectViewSet action/permission, unit and integration tests.

## Applying the supplied source package

The source package includes complete frontend/backend trees and patches against each repository's `main` base. GitHub allowed the frontend branch but denied backend branch creation (403). If `taiga-back` has no remote feature branch, create it locally from the documented base and apply `patches/taiga-back.patch` from the package:

```bash
git switch -c feature/team-standup-dashboard
git apply --check /path/to/patches/taiga-back.patch
git apply /path/to/patches/taiga-back.patch
```

Validation completed: 10 backend projection tests, 7 frontend controller tests, 6 native Django endpoint integration tests using embedded PostgreSQL with schema synchronization, Django system check, route registration, CoffeeScript/Jade/SCSS compilation and stylesheet lint. Browser checks rendered the actual template with a projection-backed fixture and covered lead/search/reset filters, photos, overdue rows, multiple assignments, idle-last ordering and mobile overflow. The full production frontend build, migration replay and live deployment/database verification remain pending.
