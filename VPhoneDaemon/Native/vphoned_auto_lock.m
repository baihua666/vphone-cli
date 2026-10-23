#import "Include/VphonedNative.h"
#include <dlfcn.h>
#include <objc/message.h>

// Use profiled's setting API, not its generated EffectiveUserSettings.plist.
// MCFeatureAutoLockTime is resolved from the running framework's exports.
bool vp_auto_lock_never(NSString **error) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/ManagedConfiguration.framework/ManagedConfiguration", RTLD_NOW);
    });
    @try {
        Class type = NSClassFromString(@"MCProfileConnection");
        NSString *const __unsafe_unretained *feature = handle
            ? (NSString *const __unsafe_unretained *)dlsym(handle, "MCFeatureAutoLockTime") : NULL;
        SEL shared = @selector(sharedConnection);
        SEL set = @selector(setValue:forSetting:);
        SEL flush = @selector(flush);
        if (!feature || !*feature || ![type respondsToSelector:shared]) {
            if (error) *error = @"ManagedConfiguration Auto-Lock setting is unavailable";
            return false;
        }
        id connection = ((id (*)(id, SEL))objc_msgSend)(type, shared);
        if (![connection respondsToSelector:set] || ![connection respondsToSelector:flush]) {
            if (error) *error = @"ManagedConfiguration cannot write Auto-Lock";
            return false;
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(connection, set, @(INT32_MAX), *feature);
        ((void (*)(id, SEL))objc_msgSend)(connection, flush);
        return true;
    } @catch (NSException *exception) {
        if (error) *error = exception.reason ?: @"ManagedConfiguration rejected Auto-Lock";
        return false;
    }
}
