# ADR 0027 — Preserve DDEV metadata across the worker boundary

Status: accepted for the Windows development preview.

The Mac card already reads PHP and database versions through DDEVConfig and DDEVStatus.
The Windows worker discarded versionsLine, while its synthetic example supplied the same
text in EngineVersion. A source-only review and a rendered example therefore missed the
production loss. The offline WorkerService request regression failed before this fix.

Add optional versionsLine to protocol v1, using the existing shared formatter. EngineVersion
keeps its Arc meaning. Older workers and hosts remain compatible. The native DDEV card shows
framework/checkout on the left and the version line on the right, with full tooltips and no
invented fallback versions. Stopped, paused and unknown projects retain configuration metadata;
health/synchronization warnings do not replace it. Compact cards hide the metadata row.

Export all tool URLs actually reported by DDEV, including xhgui. The host filters capabilities
through saved tool switches; filtering in the worker's default model made enabling xhgui
impossible. New Windows project forms default Mailpit on and xhgui off. Existing settings keep
their choices, including legacy records. Missing services never acquire a fabricated URL.

Do not duplicate the YAML parser in Windows or repurpose EngineVersion for DDEV. Qualification
covers the worker's temporary checkout files and encoded JSON, native DTO validation, six-language
full/compact/warning layouts and read-only existing-project metadata. Synthetic values alone
cannot certify worker export. The shipping Mac UI/product graph remains unchanged; release
qualification still requires native Mac and the other documented external gates.
