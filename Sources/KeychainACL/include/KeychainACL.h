#ifndef KEYCHAIN_ACL_H
#define KEYCHAIN_ACL_H

#include <Security/Security.h>

/// Builds a Keychain access control list that names no application.
///
/// C rather than Swift for one reason: the whole `SecKeychain` access-control family was
/// deprecated in 10.10 and has no modern replacement for this question, because on iOS the
/// question does not arise. Swift cannot silence a deprecation warning at a call site, and this
/// project's CI fails on warnings, so the three deprecated calls live here where a pragma can
/// say plainly that they are deliberate.
///
/// Returns NULL on failure, which the caller treats as "store it the ordinary way".
/// The returned object is owned by the caller.
SecAccessRef devdeck_open_access(CFStringRef description);

#endif
