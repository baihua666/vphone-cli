// Standalone, read-only iOS test app. Not linked into vphone or vphoned.
#import <UIKit/UIKit.h>
#include <TargetConditionals.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <errno.h>

static NSDictionary *readSysctl(const char *name, BOOL number) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0) {
        int code = errno;
        return @{ @"ok": @NO, @"errno": @(code),
                  @"error": @(strerror(code)) };
    }
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (sysctlbyname(name, data.mutableBytes, &size, NULL, 0) != 0) {
        int code = errno;
        return @{ @"ok": @NO, @"errno": @(code),
                  @"error": @(strerror(code)) };
    }
    if (number) {
        uint64_t value = 0;
        if (size != sizeof(uint32_t) && size != sizeof(uint64_t))
            return @{ @"ok": @NO, @"error": @"unexpected integer size", @"size": @(size) };
        memcpy(&value, data.bytes, size);
        return @{ @"ok": @YES, @"value": @(value), @"size": @(size) };
    }
    const char *bytes = data.bytes;
    size_t length = size ? strnlen(bytes, size) : 0;
    NSString *value = [[NSString alloc] initWithBytes:bytes length:length
                                          encoding:NSUTF8StringEncoding];
    if (!value) return @{ @"ok": @NO, @"error": @"invalid UTF-8" };
    return @{ @"ok": @YES, @"value": value };
}

static NSDictionary *collectReport(void) {
    UIDevice *device = UIDevice.currentDevice;
    struct utsname info;
    int rc = uname(&info);
    NSDictionary *unameResult = rc == 0
        ? @{ @"ok": @YES, @"machine": @(info.machine),
             @"sysname": @(info.sysname), @"release": @(info.release) }
        : @{ @"ok": @NO, @"errno": @(errno) };
    NSString *sourceHash = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TBProbeSourceSHA256"];
    return @{
        @"schema": @1,
        @"probe_source_sha256": sourceHash ?: @"unknown",
        @"timestamp": [NSISO8601DateFormatter.new stringFromDate:NSDate.date],
        @"process": @{ @"pid": @(getpid()), @"uid": @(getuid()), @"euid": @(geteuid()),
                        @"target_os_simulator": @(TARGET_OS_SIMULATOR),
                        @"scope": @"standalone iOS app; sandbox equivalence not asserted" },
        @"device": @{ @"model": device.model, @"system": device.systemName,
                       @"system_version": device.systemVersion },
        @"uname": unameResult,
        @"sysctl": @{ @"hw.machine": readSysctl("hw.machine", NO),
                       @"hw.model": readSysctl("hw.model", NO),
                       @"hw.ncpu": readSysctl("hw.ncpu", YES),
                       @"hw.memsize": readSysctl("hw.memsize", YES),
                       @"kern.osrelease": readSysctl("kern.osrelease", NO) },
        @"interpretation": @"Measurements only. No physical-device verdict or firmware deployment assertion."
    };
}

@interface ProbeViewController : UIViewController
@property(nonatomic, strong) UITextView *output;
@end

@implementation ProbeViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"VPHONE Read-only Probe";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain
        target:self action:@selector(refresh)];
    self.output = [[UITextView alloc] initWithFrame:CGRectZero];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.output.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.output];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.output.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.output.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.output.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.output.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12]
    ]];
    [self refresh];
}
- (void)refresh {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:collectReport()
        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data) { self.output.text = error.localizedDescription; return; }
    self.output.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    if (![data writeToURL:[documents URLByAppendingPathComponent:@"report.json"]
                 options:NSDataWritingAtomic error:&error]) {
        self.output.text = [self.output.text stringByAppendingFormat:@"\nSave error: %@", error];
    }
    // Public log payload deliberately excludes device identifiers and user data.
    NSLog(@"TB_VPHONE_PROBE_REPORT %@", [[NSString alloc] initWithData:data
                                                          encoding:NSUTF8StringEncoding]);
}
@end

@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc]
        initWithRootViewController:ProbeViewController.new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class));
    }
}
