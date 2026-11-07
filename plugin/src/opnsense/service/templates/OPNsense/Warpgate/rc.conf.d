{# no secrets here: this file ends up 0644; the admin token is in private/warpgate.env (0600) #}
{% if helpers.exists('OPNsense.Warpgate.enabled') and OPNsense.Warpgate.enabled == '1' %}
{%   set wg = OPNsense.Warpgate %}
warpgate_enable="YES"
warpgate_debug="{{ {'debug': '-d', 'trace': '-dd'}.get(wg.debug, '') }}"
warpgate_env_file="/usr/local/etc/warpgate/private/warpgate.env"
{%   if wg.admin_token %}
warpgate_run_flags="--enable-admin-token"
{%   endif %}
{% else %}
warpgate_enable="NO"
{% endif %}
