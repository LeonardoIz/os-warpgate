<script>
    $(document).ready(function () {
        mapDataToFormUI({'mainform': '/api/warpgate/general/get'}).done(function (data) {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
            updateServiceControlUI('warpgate');
            const g = data.mainform.general;
            const host = g.http_external_host || g.external_host || window.location.hostname;
            $('#openWarpgate').attr('href', 'https://' + host + ':' + (g.http_external_port || g.http_port) + '/');
        });

        $('#reconfigureAct').SimpleActionButton({
            onPreAction: function () {
                const dfObj = new $.Deferred();
                saveFormToEndpoint('/api/warpgate/general/set', 'mainform', function () { dfObj.resolve(); }, true, function () { dfObj.reject(); });
                return dfObj;
            },
            onAction: function () {
                updateServiceControlUI('warpgate');
                setTimeout(showInitialPassword, 3000);  // the first start creates the admin user
            }
        });

        // base_tabs_content adds a save button per tab; the single Apply below saves all tabs (as IPsec does)
        $('[id^="save_warpgate-"]').closest('tr').hide();

        // open the tab named in the URL hash, else the first one; keep the hash in sync
        const $hashTab = window.location.hash ? $('#maintabs a[href="' + window.location.hash + '"]') : $();
        ($hashTab.length ? $hashTab : $('#maintabs a:first')).tab('show');
        $('#maintabs a').on('shown.bs.tab', function (e) { history.replaceState(null, null, e.target.hash); });

        $('#{{ formGridProvider['table_id'] }}').UIBootgrid({
            search: '/api/warpgate/general/search_provider',
            get: '/api/warpgate/general/get_provider/',
            set: '/api/warpgate/general/set_provider/',
            add: '/api/warpgate/general/add_provider/',
            del: '/api/warpgate/general/del_provider/',
            toggle: '/api/warpgate/general/toggle_provider/'
        });

        /* initial admin password */
        function showInitialPassword() {
            ajaxGet('/api/warpgate/tools/initial_password', {}, function (data) {
                $('#initialPassword').text(data.password || '');
                $('#initialPasswordBox').toggle(!!data.password);
            });
        }
        showInitialPassword();
        $('#dismissInitialPassword').click(function () {
            ajaxCall('/api/warpgate/tools/dismiss_initial_password', {}, showInitialPassword);
        });

        /* tools: run a warpgate command and show its result */
        function showResult(title, data) {
            const $msg = $('<div>');
            if (data.password) {
                $msg.append($('<p>').append('{{ lang._('New password (shown only once):') }} ', $('<code>').text(data.password)));
            }
            if (data.output) {
                $msg.append($('<pre style="white-space: pre-wrap; max-height: 25em;">').text(data.output));
            }
            BootstrapDialog.show({
                type: data.ok ? BootstrapDialog.TYPE_INFO : BootstrapDialog.TYPE_DANGER,
                title: title,
                message: $msg
            });
        }
        function runTool(btn, endpoint, payload, confirmText) {
            const title = $(btn).text().trim();
            const run = function () {
                const $btn = $(btn).prop('disabled', true);
                const done = function (data) { $btn.prop('disabled', false); showResult(title, data || {ok: false}); };
                payload === null ? ajaxGet(endpoint, {}, done) : ajaxCall(endpoint, payload, done);
            };
            confirmText ? BootstrapDialog.confirm({
                title: title, message: confirmText, type: BootstrapDialog.TYPE_WARNING,
                callback: function (yes) { if (yes) run(); }
            }) : run();
        }
        ajaxGet('/api/warpgate/tools/version', {}, function (data) { $('#warpgateVersion').text(data.ok ? data.output : '-'); });
        $('#toolCheck').click(function () { runTool(this, '/api/warpgate/tools/check', null); });
        $('#toolClientKeys').click(function () { runTool(this, '/api/warpgate/tools/client_keys', null); });
        $('#toolRecover').click(function () {
            runTool(this, '/api/warpgate/tools/recover_access', {username: $('#toolRecoverUser').val()},
                "{{ lang._('Adds a new password to this user and sets its web login policy to password only. Continue?') }}");
        });
        $('#toolCreateUser').click(function () {
            runTool(this, '/api/warpgate/tools/create_user', {username: $('#toolNewUser').val(), role: $('#toolNewUserRole').val()});
        });
        $('#toolCopyDb').click(function () {
            runTool(this, '/api/warpgate/tools/copy_database', {url: $('#toolCopyDbUrl').val()},
                "{{ lang._('Copies all data into the target database (which must be empty). The running instance keeps using its current database. Continue?') }}");
        });
        $('#toolMigrate').click(function () {
            runTool(this, '/api/warpgate/tools/migrate_database',
                {steps: $('#toolMigrateSteps').val(), destructive: $('#toolMigrateDestructive').is(':checked') ? '1' : '0'},
                "{{ lang._('Changes the database schema. Stop the service and back up /var/db/warpgate first. Continue?') }}");
        });
    });
</script>

<div class="alert alert-info" id="initialPasswordBox" style="display: none;">
    {{ lang._('Initial admin credentials: user %s, password %s') | format('<code>admin</code>', '<code id="initialPassword"></code>') }}
    <button class="btn btn-xs btn-default pull-right" id="dismissInitialPassword" type="button">{{ lang._('Dismiss') }}</button>
    <br/><small>{{ lang._('Change the password in the Warpgate admin UI, then dismiss this message: it deletes the stored initial password.') }}</small>
</div>

<ul class="nav nav-tabs" role="tablist" id="maintabs">
    {{ partial('layout_partials/base_tabs_header', ['formData': formSettings]) }}
    <li><a data-toggle="tab" href="#sso" role="tab">{{ lang._('SSO') }}</a></li>
    <li><a data-toggle="tab" href="#tools" role="tab">{{ lang._('Tools') }}</a></li>
</ul>

<form id="mainform">
    <div class="content-box tab-content">
        {{ partial('layout_partials/base_tabs_content', ['formData': formSettings]) }}
        <div id="sso" class="tab-pane fade">
            <p style="padding: 1em 1em 0;">{{ lang._('OpenID Connect providers for logging in to Warpgate. Apply to activate changes.') }}</p>
            {{ partial('layout_partials/base_bootgrid_table', formGridProvider) }}
        </div>
        <div id="tools" class="tab-pane fade" style="padding: 1em;">
            <p>
                {{ lang._('Version') }}: <code id="warpgateVersion">…</code>
                <a class="btn btn-default btn-xs" id="openWarpgate" target="_blank" rel="noopener" style="margin-left: 1em;">{{ lang._('Open Warpgate admin UI') }}</a>
            </p>
            <p class="text-muted">{{ lang._("Targets, users, roles and session recordings (disk or S3 storage) are managed in the Warpgate admin UI. These tools run Warpgate's own commands.") }}</p>

            <h4>{{ lang._('Diagnostics') }}</h4>
            <button class="btn btn-default" id="toolCheck" type="button">{{ lang._('Check configuration') }}</button>
            <button class="btn btn-default" id="toolClientKeys" type="button">{{ lang._('Show SSH client keys') }}</button>
            <p class="text-muted"><small>{{ lang._("SSH client keys are what Warpgate presents to SSH targets: add them to the targets' authorized_keys.") }}</small></p>

            <h4>{{ lang._('Users') }}</h4>
            <div class="form-inline" style="margin-bottom: .5em;">
                <input class="form-control" id="toolRecoverUser" type="text" placeholder="admin" value="admin"/>
                <button class="btn btn-default" id="toolRecover" type="button">{{ lang._('Recover access') }}</button>
                <small class="text-muted">{{ lang._('Sets a new random password, e.g. when locked out of the admin UI.') }}</small>
            </div>
            <div class="form-inline">
                <input class="form-control" id="toolNewUser" type="text" placeholder="{{ lang._('username') }}"/>
                <input class="form-control" id="toolNewUserRole" type="text" placeholder="{{ lang._('role (optional), e.g. warpgate:admin') }}"/>
                <button class="btn btn-default" id="toolCreateUser" type="button">{{ lang._('Create user') }}</button>
                <small class="text-muted">{{ lang._('With a random password.') }}</small>
            </div>

            <div class="panel panel-warning" style="margin-top: 2em;">
                <div class="panel-heading">{{ lang._('Advanced: database') }}</div>
                <div class="panel-body">
                    <div class="form-inline" style="margin-bottom: .5em;">
                        <input class="form-control" id="toolCopyDbUrl" type="text" size="50" placeholder="postgres://user:password@host/warpgate"/>
                        <button class="btn btn-default" id="toolCopyDb" type="button">{{ lang._('Copy database') }}</button>
                        <small class="text-muted">{{ lang._('Then set General: Database URL to it and apply.') }}</small>
                    </div>
                    <div class="form-inline">
                        <input class="form-control" id="toolMigrateSteps" type="number" value="1" style="width: 6em;"/>
                        <label><input id="toolMigrateDestructive" type="checkbox"/> {{ lang._('allow destructive') }}</label>
                        <button class="btn btn-default" id="toolMigrate" type="button">{{ lang._('Run database migrations') }}</button>
                        <small class="text-muted">{{ lang._('Positive applies, negative reverts. Warpgate migrates on start; use only for recovery.') }}</small>
                    </div>
                </div>
            </div>
        </div>
    </div>
</form>

{{ partial('layout_partials/base_apply_button', {'data_endpoint': '/api/warpgate/service/reconfigure', 'data_service_widget': 'warpgate', 'data_exclude_scope': 'tools'}) }}
{{ partial('layout_partials/base_dialog', ['fields': formDialogProvider, 'id': formGridProvider['edit_dialog_id'], 'label': lang._('Edit SSO provider')]) }}
