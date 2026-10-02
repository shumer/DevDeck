# 24. Windows cards follow account setup and a visible catalog

Date: 2026-10-01. Windows development preview only; the Mac product graph remains unchanged.

Account metadata could be saved successfully without showing any remote widget. Unlike the Mac
catalog/menu, Windows required a second manual card-creation operation and had no tray visibility
list. With several accounts this also made it unclear whether to create a card per account.

Use one Windows-only Core catalog for startup migration, account saves and visibility controls.
Reuse the persisted Mac identifiers and default GitHub PR/Inbox visibility. Actions stays hidden;
GitLab setup shows MR. The tray and Settings/Cards list every implemented remote type even before
setup. Local projects retain grouped tray visibility. Missing-account activation opens the matching
provider form; toggling never verifies/writes credentials or changes notification read state.

An existing card of the same kind takes precedence, including an explicit hidden state. Keep its
ID, account scope, title, placement and collapsed preference. New built-ins aggregate all provider
accounts and explicitly persist UseAllAccounts; legacy cards default to manual scope. New accounts
join automatic scopes without recreating cards. Built-in hide/show reuses the same record and
closes hidden windows/polling. Initial placement searches free work-area positions without moving
existing cards; a crowded area uses the least overlapping reachable position.
Removing an account detaches references instead of blocking deletion. Automatic scopes retain
their visibility preference while no enabled account exists, create no window/fetch, and resume
after setup. Empty manual scopes disable. No real account is removed during qualification.

Keeping the manual creation requirement was rejected because it caused the reported invisible
account setup. Creating one widget per account was rejected because Mac aggregates accounts and
it would clutter the desktop. Re-enabling all existing cards on every save was rejected because it
would erase hidden preferences. Work in flight remains disabled with a migration explanation.

Qualification uses artificial Core/native fixtures plus an explicit read-only saved-account check.
Native Mac, external desktop/network and release gates remain required separately.
