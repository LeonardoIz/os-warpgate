{% if helpers.exists('OPNsense.Warpgate.enabled') and OPNsense.Warpgate.enabled == '1' %}
{%   set wg = OPNsense.Warpgate %}
warpgate_enable="YES"
warpgate_debug="{{ {'debug': '-d', 'trace': '-dd'}.get(wg.debug, '') }}"
{%   if wg.admin_token %}
warpgate_run_flags="--enable-admin-token"
warpgate_env="WARPGATE_ADMIN_TOKEN={{ wg.admin_token }}"
{%   endif %}
{% else %}
warpgate_enable="NO"
{% endif %}
