# Azure Virtual Desktop

Automation, monitoring and infrastructure as code for Azure Virtual Desktop (AVD), shared by [DW Consult](https://dwconsult.tech).

This repository is for AVD administrators and engineers. Each folder holds a project you can deploy on its own, with its own documentation.

## Projects

| Project | What it does | Start here |
| --- | --- | --- |
| [AVD monitoring baseline](monitoring/monitoring-baseline/) | Alert rules for host pools, session hosts, FSLogix, scaling plans, Azure Files, Azure NetApp Files and Service Health, deployed with Bicep. Based on Microsoft's Azure Monitor Baseline Alerts (AMBA). | [README](monitoring/monitoring-baseline/README.md) |

More background is on the [DW Consult blog](https://dwconsult.tech/).

## Releases

Each project has its own version tags, for example `monitoring-baseline-v1.0.1`. See [Releases](https://github.com/dwconsultbe/azure-virtual-desktop/releases).

## Feedback and security

- Questions, ideas and bugs: open an [issue](https://github.com/dwconsultbe/azure-virtual-desktop/issues).
- Security problems: report them privately under **Security** > **Report a vulnerability**. Please do not open a public issue.

## License

[MIT](LICENSE). These are community examples, not official Microsoft solutions. Test them outside production first.
