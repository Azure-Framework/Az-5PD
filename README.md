# Az 5PD

Az 5PD is a FiveM police simulation, MDT, callout, dispatch, and scene-tools resource for Az-Framework, QBCore, ESX, Gimic Core, and standalone ACE permission servers.

[Framework Docs](https://madebyazure.com/framework/) | [Discord Support](https://discord.gg/tBg2U6CTHE)

## Status

- Resource: `Az-5PD`
- Runtime: `cerulean`
- Framework mode: `auto`, `az`, `qb`, `esx`, `gimic`, or `standalone`

## Install

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_target

# Start one supported framework before Az-5PD:
# ensure Az-Framework
# ensure qb-core
# ensure es_extended
# ensure gimicCore

ensure Az-5PD
```

## Framework Modes

Set one clear framework value in `config.lua`:

```lua
Config.Framework = 'auto'
```

Supported values:

```lua
Config.Framework = 'auto'
Config.Framework = 'az'
Config.Framework = 'qb'
Config.Framework = 'esx'
Config.Framework = 'gimic'
Config.Framework = 'standalone'
```

`auto` checks frameworks in this order:

```lua
Config.FrameworkPriority = { 'gimic', 'qb', 'esx', 'az', 'standalone' }
```

If your resource names are custom, change them here:

```lua
Config.FrameworkResources = {
  gimic = 'gimicCore',
  qb = 'qb-core',
  esx = 'es_extended',
  az = 'Az-Framework'
}
```

## Job Access

Az 5PD grants police access when the detected framework reports an allowed law-enforcement job or department.

```lua
Config.Jobs.allowed = {
  'bcso',
  'sheriff',
  'lspd',
  'police',
  'sast',
  'state',
  'trooper',
  'leo'
}
```

QBCore servers can also use `job.type = 'leo'`. Set `Config.FrameworkRequireDuty = true` if you want QBCore `job.onduty` to be required.

Gimic Core uses `exports['gimicCore']:IsOnLEODuty(source)` and `GetPlayerDepartment(source)`.

## Standalone ACE

Standalone mode does not require a roleplay framework. Enable it and grant ACE permissions:

```lua
Config.Framework = 'standalone'
```

## Framework Debugging

Turn on framework debug when access, duty, or ACE checks are not behaving how you expect:

```lua
Config.FrameworkDebug = true
```

When enabled, Az 5PD prints framework selection, resource state, job extraction, duty checks, allowed-job checks, supervisor checks, ACE permission checks, and reward routing.

```cfg
add_ace group.admin az_5pd.open allow
add_ace group.admin az_5pd.supervisor allow
add_ace group.admin az_5pd.dispatch allow
add_ace group.admin az_5pd.admin allow

# Only needed if your admin group is not already assigned by txAdmin or another permissions file:
add_principal identifier.license:YOUR_LICENSE_HERE group.admin
```

## Optional Integration

- `Az-MDT`, `az_mdt`, or `Az-Mdt-Standalone` for MDT call sync.
- `ox_target` for target shortcuts.
- `ox_lib` for menus, dialogs, and notifications.
- `oxmysql` for MDT and accountability storage.

## Notes

- Citation rewards pay through QBCore, ESX, or Az-Framework money APIs when available.
- Gimic Core duty and department data come from Gimic exports.
- Standalone ACE mode handles access, but money rewards are skipped unless a framework money API is available.

## Support

- Docs: https://madebyazure.com/framework/
- Discord: https://discord.gg/tBg2U6CTHE
