# Helpdesk guide

**For:** the helpdesk that receives the alert e-mails.

**Result:** you know what an alert means, whether users are affected, and what to do first. You do not need to know how the solution is built.

If you deploy or configure the solution, use the [administrator guide](administrator-guide.md). For the full background, see the [technical documentation](technical-documentation.md).

## What does the monitoring do?

Our users work on virtual Windows desktops in Azure (Azure Virtual Desktop, or AVD). The monitoring watches those desktops and the storage behind them, and sends an e-mail when something goes wrong or is about to go wrong. It checks things such as:

- Is there still room for more users, or is the environment almost full?
- Is a desktop machine (called a **session host**) healthy?
- Can users connect, and does their profile load?
- Is the file storage that holds the profiles running full or slow?
- Is Microsoft itself reporting a problem with Azure Virtual Desktop?
- Is the monitoring still working?

## How to read an alert e-mail

An alert has a **name**, a **severity** and a **description**. Often it also shows which **host**, **user**, **disk** or **file share** is affected.

| Severity | Meaning | Suggested handling |
|---|---|---|
| **Sev 1 – Error** | Users are, or soon will be, affected. | Act right away. |
| **Sev 2 – Warning** | Something needs attention soon. | Look at it the same day. |
| **Sev 3 – Informational** | Good to know. No direct impact yet. | Note it and keep an eye on it. |

Good to know:

- **You get one e-mail per problem, not a new one every few minutes.** An alert is *fired* once and stays open while the problem lasts.
- **Each affected item gets its own alert.** Two hosts with a full disk give two e-mails. That is normal.
- **An alert closes by itself** when the problem is gone, and sometimes a while after the last event. **"Resolved" does not always mean "fixed".** For example, the alert about a removed scaling plan closes by itself while the plan is still missing.
- **Only alerts that the administrator switched on send e-mail.** After a new installation only the most important alerts (the "core" set) are on.

## What to do when an alert arrives

1. **Read the name and severity.** Find the alert in the tables below.
2. **Check whether users are affected.** The tables tell you if users can still work.
3. **Do the first step** from the table. It is safe: it only looks and checks. Do not change or restart anything unless the table says so.
4. **Write down** what you saw: the alert name, the time, the host or user, and what you did.
5. **Escalate** when the first step does not help, or when users cannot work: pass it on to the administrator with those notes.

Escalation contact: **(fill in: name, phone number and mailbox of the administrator on duty)**

## What each alert means

> [!TIP]
> **How to find an alert in these tables:** the alert name in the e-mail contains the short code from the first column. For example, `avd-ar-hp-prod-capacity-85-x7k2` is **capacity-85** for host pool **hp-prod**. The collector alerts are shared and have no host pool in their name.

### The monitoring itself

If these alerts fire, other alerts may stay silent without anyone noticing. Treat them as important.

| Alert | Sev | What it means | First step |
|---|---|---|---|
| collector-failed | 2 | One of the two small scripts that gather the data (the "collectors") failed. | Open the Automation Account, go to **Jobs** and note the error of the failed job. Escalate. |
| collector-stale | 2 | A collector has not delivered data for 45 minutes. | Check in the Automation Account that the schedules are on and that jobs are running. Escalate if they are not. |
| diagnostic-data-missing | 2 | Users are connected, but the health data of the desktops is not arriving. Many other alerts are blind meanwhile. | Escalate. The administrator must check the diagnostic settings of the host pool. |

### Users cannot connect or the environment is full

| Alert | Sev | What it means | First step |
|---|---|---|---|
| no-resources | 1 | Users could not connect because no healthy desktop machine was available. One e-mail per host pool; the alert shows how many users were refused, with some names. | Users cannot work. Check the host alerts below and escalate. |
| connection-failure | 3 | Several users failed to connect, with the same error. | Ask the affected users what they see, note the error code in the alert and escalate if it continues. |
| capacity-50 | 3 | The environment is 50% to 85% full. | Nothing to do now. Keep an eye on it. |
| capacity-85 | 2 | The environment is 85% to 95% full. | Check that extra machines are starting. Escalate if the number of users keeps growing. |
| capacity-95 | 1 | The environment is 95% full or more. New users may be refused. | Escalate right away. More capacity is needed. |

### A desktop machine has a problem

The alert shows the name of the machine (the "session host").

| Alert | Sev | What it means | First step |
|---|---|---|---|
| health-check | 1 | A machine has failed one of its self-checks for at least 5 minutes. The alert names the check (for example DomainJoin or FSLogix). A short failure while the machine starts is ignored. | Note the machine and the check. Escalate. The machine may need to be taken out of use. |
| personal-unhealthy | 1 | The personal desktop of a user is unhealthy. The alert shows the user. | That user cannot work. Note the machine and the user, then escalate. |
| agent-upgrade | 3 | The software that connects the machine to AVD failed to update or is stuck. | Note the machine. A restart of the machine often helps, but ask the administrator first. |
| drained-idle | 3 | A machine has been closed to new users and empty for 24 hours, while still running and costing money. | Pass it on to the administrator: it can be switched off or put back into use. |
| memory2GB | 2 | A machine has little memory left (2 GB or less). | Users may notice slowness. Note the machine and report it. |
| memory1GB | 1 | A machine has very little memory left (1 GB or less). | Users will notice problems. Escalate. |
| localDiskFree10 | 2 | A disk of a machine has 10% free space or less. | Note the machine and the disk. Report it. |
| localDiskFree5 | 1 | A disk has 5% free space or less. | Escalate soon. A full disk can stop users from signing in. |
| cpu85 | 2 | The processor of a machine is very busy for a long time (85% or more). | Users may notice slowness. Note the machine. |
| cpu95 | 1 | The processor is almost at its limit (95% or more). | Escalate. Users are probably slow. |
| osDiskBandwidth85 / osDiskBandwidth95 | 2 / 1 | The OS disk bandwidth is at 85% or 95% or more. | Check for heavy disk activity and review the disk SKU. |

### The profile of a user does not load (FSLogix)

FSLogix is the technology that loads a user's personal settings and files when they sign in.

| Alert | Sev | What it means | First step |
|---|---|---|---|
| fslogix-free-5 | 2 | The profile of a user is almost full (less than 5% free). | Note the user. Ask the administrator to enlarge the profile or clean it up. |
| fslogix-free-2 | 1 | The profile of a user is full (less than 2% free). | Report it today. The user may get errors. |
| fslogix-disk-in-use | 2 | The profile is still open on another machine. | Check whether the user has a session open somewhere else and sign that session off. |
| fslogix-attach | 1 | A profile could not be loaded. | Several users on one machine point to a machine or storage problem. Escalate. |
| fslogix-network | 1 | A profile failed because of a network problem. | Escalate. |
| fslogix-service-disabled | 1 | The profile service is switched off on a machine. | Escalate. |
| fslogix-compaction | 2 | Housekeeping of the profile files failed. | Not urgent. Report it to the administrator. |

### The file storage for the profiles

| Alert | Sev | What it means | First step |
|---|---|---|---|
| file-share-free-15 | 2 | The storage for the profiles has 15% free space or less. | Report it. The administrator must enlarge it. |
| file-share-free-5 | 1 | The storage has 5% free space or less. | Escalate right away. Profiles can no longer be saved when it is full. |
| filesAvailability | 1 | The file storage is not fully available. | Check the Azure Service Health page. Escalate. |
| filesLatency50 / filesServerLatency50 | 2 | The file storage is slow (more than 50 ms). | Users may sign in slowly. Report it. |
| filesLatency100 / filesServerLatency100 | 1 | The file storage is very slow (more than 100 ms). | Escalate. |
| files-throttling | 2 | Azure is holding back the storage because it is used too heavily. | Report it. The storage is probably too small or too slow. |
| anfVolumeFree15 / anfVolumeFree5 | 2 / 1 | (Only when used.) A NetApp storage volume is 85% or 95% full. | Report it. At 95% escalate. |

### The scaling plan (automatic starting and stopping of machines)

| Alert | Sev | What it means | First step |
|---|---|---|---|
| scaling-disabled-4h | 3 | Automatic scaling has been switched off for 4 hours. | Ask the administrator whether this was on purpose (for example maintenance). |
| scaling-disabled-24h | 2 | Still switched off after a full day. It was probably forgotten. | Report it. |
| scaling-removed | 3 | The scaling plan was removed from the host pool. This alert closes by itself, even though the plan is still gone. | Report it, and do not rely on the alert closing. |
| autoscale-failures | 3 | (Only when used.) Automatic scaling keeps failing. | Report it, with the error shown in the alert. |

### Messages from Microsoft

| Alert | What it means | First step |
|---|---|---|
| service-health-incident | Microsoft reports a problem with Azure Virtual Desktop. | Open the Azure Service Health page. Tell users that Microsoft is working on it. There is usually nothing to repair. |
| service-health-advisory | Microsoft gives information or asks us to do something. | Read the message. "Action required" means a change is needed before a deadline. Pass it on. |
| service-health-maintenance | Microsoft plans maintenance. | Note the date and time. |
| service-health-security | Microsoft publishes a security notice. | Pass it on to the administrator. |

## Frequently asked questions

**The alert is "Resolved". Is the problem fixed?**
Not always. An alert closes when the check no longer finds the problem. That can mean that it is fixed, but also that the data stopped arriving. If you are not sure, look at the machine, the user or the storage itself.

**I received no e-mail, but users are complaining.**
The alert may be switched off, or the data does not arrive. Check whether **collector-failed** or **collector-stale** has fired and escalate to the administrator.

**I received the same alert several times.**
Each machine, disk, user or share gets its own alert. Look at the name of the item in the alert: it is probably a different one each time.

**An alert is about a machine that is switched off.**
For personal desktops, machines that were switched off on purpose are left out. For other alerts, switched-off machines normally do not report anything. If you still get alerts for a stopped machine, report it to the administrator.

**Can I change an alert?**
No. Thresholds and alerts are managed by the administrator. Report alerts that give too many or too few messages.

## Where to look

- **Alerts:** Azure portal, **Monitor**, **Alerts**. There you see which alerts are open and which have closed.
- **The collectors:** Azure portal, the Automation Account and resource group used by your deployment. Under **Jobs** you see the runs and their errors.
- **Microsoft problems:** Azure portal, **Service Health**.

## More information

- [Administrator guide](administrator-guide.md): installation, settings, pipeline and the source notice for adapted material.
- [Technical documentation](technical-documentation.md): the full alert catalog, with how often each alert checks and which data it uses.
- The alert ideas and parts of the queries were adapted from Microsoft's AMBA AVD baseline. The source notice is in the administrator guide.
