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

`Config.Framework.mode = 'auto'` detects supported frameworks in this order:

```lua
Config.Framework.prefer = { 'gimic', 'qb', 'esx', 'az', 'standalone' }
```

Use a forced mode if your server runs multiple frameworks at once:

```lua
Config.Framework.mode = 'qb'
Config.Framework.mode = 'esx'
Config.Framework.mode = 'gimic'
Config.Framework.mode = 'standalone'
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

QBCore servers can also use `job.type = 'leo'`. Set `Config.Framework.requireDuty = true` if you want QBCore `job.onduty` to be required.

Gimic Core uses `exports['gimicCore']:IsOnLEODuty(source)` and `GetPlayerDepartment(source)`.

## Standalone ACE

Standalone mode does not require a roleplay framework. Enable it and grant ACE permissions:

```lua
Config.Framework.mode = 'standalone'
Config.Standalone = true
```

```cfg
add_ace group.admin az_5pd.open allow
add_ace group.admin az_5pd.supervisor allow
add_ace group.admin az_5pd.dispatch allow
add_ace group.admin az_5pd.admin allow
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
