#include "include/KeychainACL.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

SecAccessRef devdeck_open_access(CFStringRef description) {
    SecAccessRef access = NULL;
    if (SecAccessCreate(description, NULL, &access) != errSecSuccess || access == NULL) {
        return NULL;
    }

    CFArrayRef acls = NULL;
    if (SecAccessCopyACLList(access, &acls) != errSecSuccess || acls == NULL) {
        CFRelease(access);
        return NULL;
    }

    for (CFIndex index = 0; index < CFArrayGetCount(acls); index++) {
        SecACLRef acl = (SecACLRef)CFArrayGetValueAtIndex(acls, index);

        CFArrayRef applications = NULL;
        CFStringRef aclDescription = NULL;
        SecKeychainPromptSelector prompt = 0;
        if (SecACLCopyContents(acl, &applications, &aclDescription, &prompt) != errSecSuccess) {
            continue;
        }
        if (applications != NULL) {
            CFRelease(applications);
        }

        // A NULL application list is the documented way to say "any application", and is what
        // the `-A` flag of the `security` command writes.
        SecACLSetContents(acl, NULL, aclDescription != NULL ? aclDescription : description, prompt);
        if (aclDescription != NULL) {
            CFRelease(aclDescription);
        }
    }

    CFRelease(acls);
    return access;
}

#pragma clang diagnostic pop
