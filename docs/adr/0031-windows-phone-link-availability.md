# Windows phone-link availability

Date: 2026-10-01
Status: Accepted for the Windows development preview

The QR menu was inactive for normal DDEV sites without explaining why. This was inherited from
the Mac loopback-only policy: DDEV selects a project by hostname, so replacing `*.ddev.site` with
an IP loses its route. The current real web container also binds its direct HTTP port to loopback.
Generating a code for that port would not establish phone access.

Keep automatic rewriting limited to loopback or the exact physical Windows LAN IPv4 already
present in the site URL. The QR menu opens localized availability guidance when no usable address
exists. Running expanded cards expose this action; stopped and compact cards retain it in their
menu, while lifecycle operations hide/disable it. No service, network or firewall is changed.

An optional card-level `phoneURL` accepts an explicitly chosen HTTP(S) URL already accessible
from the phone. It is independent of the worker/readiness/browser URL and defaults to absent for
old settings. Reject credentials, controls, excessive lengths and domains/IPs that point at the
phone itself or have unusable scope. This field does not verify or create external reachability.
External DNS, a direct DDEV HTTP port and Windows/WSL network access are configured explicitly
outside the automatic QR path; see the [DDEV guide](https://docs.ddev.com/en/stable/users/topics/sharing/).

Copy copies the exact encoded address and dismisses. Fresh snapshots update an open popup;
failed status reads invalidate it until a fresh snapshot arrives. Deterministic native tests use
synthetic LAN addresses and a fake clipboard; an independent decoder checks the QR encoder.
Real same-network phone access remains a qualification gate. Original Mac sources/resources and
the shared worker protocol remain unchanged.
