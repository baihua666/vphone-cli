#import <Foundation/Foundation.h>
#include <dlfcn.h>
#import "../Native/Include/VphonedNative.h"

static bool hasFeature = true;
static bool canWrite = true;
static bool rejects = false;
static int writes = 0;
static int flushes = 0;
static NSString *const featureName = @"maxInactivity";

void *vp_test_dlopen(const char *path, int flags) { return (void *)1; }
void *vp_test_dlsym(void *handle, const char *name) {
    NSCAssert(strcmp(name, "MCFeatureAutoLockTime") == 0, @"Must resolve the framework feature");
    return hasFeature ? (void *)&featureName : NULL;
}

@interface MCProfileConnection : NSObject
+ (instancetype)sharedConnection;
- (void)setValue:(id)value forSetting:(id)setting;
- (void)flush;
@end

@implementation MCProfileConnection
+ (instancetype)sharedConnection { return [self new]; }
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(setValue:forSetting:) && !canWrite) return NO;
    return [super respondsToSelector:selector];
}
- (void)setValue:(id)value forSetting:(id)setting {
    if (rejects) [NSException raise:@"ProfiledFailure" format:@"setting denied"];
    NSAssert([value isEqual:@(INT32_MAX)], @"Must use Never");
    NSAssert([setting isEqual:featureName], @"Must use the exported setting");
    writes++;
}
- (void)flush { flushes++; }
@end

int main(void) {
    @autoreleasepool {
        NSString *error = nil;
        NSCAssert(vp_auto_lock_never(&error), @"Setting should succeed");
        NSCAssert(writes == 1 && flushes == 1 && error == nil, @"Must flush the system setter");
        hasFeature = false;
        NSCAssert(!vp_auto_lock_never(&error) && error != nil, @"Absent symbols must fail");
        hasFeature = true;
        canWrite = false;
        NSCAssert(!vp_auto_lock_never(&error), @"Absent setter must fail");
        canWrite = true;
        rejects = true;
        NSCAssert(!vp_auto_lock_never(&error) && [error containsString:@"denied"], @"Preserve private API errors");
        NSCAssert(writes == 1 && flushes == 1, @"Failures must not flush or report writes");
        puts("Auto-Lock native tests passed: write, flush, missing symbol, missing setter, rejection");
    }
}
