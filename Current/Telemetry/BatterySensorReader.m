#import "BatterySensorReader.h"
#import <TargetConditionals.h>
#import <dlfcn.h>
#import <math.h>

// Private IOHID ABI on arm64: event types/fields/options are uint32_t,
// matching events and clients are CF objects, and IOHIDFloat is double.
typedef CFTypeRef (*CreateClientFunction)(CFAllocatorRef);
typedef void (*SetMatchingFunction)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*CopyServicesFunction)(CFTypeRef);
typedef CFTypeRef (*CopyPropertyFunction)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*CopyEventFunction)(CFTypeRef, uint32_t, CFTypeRef, uint32_t);
typedef double (*GetFloatFunction)(CFTypeRef, uint32_t);
typedef CFDictionaryRef (*CopyAdapterFunction)(void);

@implementation BatterySensorReading

- (instancetype)initWithSensors:(NSArray<NSDictionary<NSString *, id> *> *)sensors
                 adapterDetails:(NSDictionary<NSString *, id> *)adapterDetails
                    diagnostics:(NSDictionary<NSString *, NSString *> *)diagnostics
                       duration:(NSTimeInterval)duration {
    self = [super init];
    if (self) {
        _sensors = [sensors copy];
        _adapterDetails = [adapterDetails copy];
        _diagnostics = [diagnostics copy];
        _duration = duration;
    }
    return self;
}

@end

@interface BatterySensorReader () {
    void *_library;
    CFTypeRef _client;
    SetMatchingFunction _setMatching;
    CopyServicesFunction _copyServices;
    CopyPropertyFunction _copyProperty;
    CopyEventFunction _copyEvent;
    GetFloatFunction _getFloat;
    CopyAdapterFunction _copyAdapter;
    NSString *_failure;
}
- (BatterySensorReading *)readSensors;
- (NSArray<NSDictionary<NSString *, id> *> *)readMatching:(NSDictionary *)matching
                                             eventType:(uint32_t)eventType
                                          allowedNames:(NSArray<NSString *> *)allowedNames
                                           diagnostics:(NSMutableDictionary<NSString *, NSString *> *)diagnostics
                                                 label:(NSString *)label;
@end

@implementation BatterySensorReader

+ (BatterySensorReading *)readingWithError:(NSError **)error {
#if TARGET_OS_SIMULATOR
    // Never present the Mac host's sensors or power adapter as iPhone telemetry.
    if (error) {
        *error = [NSError errorWithDomain:@"Current.BatterySensors"
                                    code:1
                                userInfo:@{NSLocalizedDescriptionKey:
                                    @"The simulator has no iPhone power sensors. "
                                     "Host-computer IOHID and adapter reads are disabled."}];
    }
    return nil;
#else
    static BatterySensorReader *reader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reader = [[BatterySensorReader alloc] init];
    });
    // A second IOHID client may not produce usable readings. Source toggles,
    // foreground transitions and refreshes must reuse this same instance.
    @synchronized (reader) {
        if (reader->_failure) {
            if (error) {
                *error = [NSError errorWithDomain:@"Current.BatterySensors"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey: reader->_failure}];
            }
            return nil;
        }
        return [reader readSensors];
    }
#endif
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
#if !TARGET_OS_SIMULATOR
    _library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    if (!_library) {
        _failure = @"The IOHID library is unavailable on this OS.";
        return self;
    }
    CreateClientFunction createClient =
        (CreateClientFunction)dlsym(_library, "IOHIDEventSystemClientCreate");
    _setMatching = (SetMatchingFunction)dlsym(_library, "IOHIDEventSystemClientSetMatching");
    _copyServices = (CopyServicesFunction)dlsym(_library, "IOHIDEventSystemClientCopyServices");
    _copyProperty = (CopyPropertyFunction)dlsym(_library, "IOHIDServiceClientCopyProperty");
    _copyEvent = (CopyEventFunction)dlsym(_library, "IOHIDServiceClientCopyEvent");
    _getFloat = (GetFloatFunction)dlsym(_library, "IOHIDEventGetFloatValue");
    _copyAdapter = (CopyAdapterFunction)dlsym(_library, "IOPSCopyExternalPowerAdapterDetails");
    if (!createClient || !_setMatching || !_copyServices || !_copyProperty || !_copyEvent || !_getFloat) {
        _failure = @"The required read-only IOHID sensor APIs are unavailable on this OS.";
        return self;
    }
    _client = createClient(kCFAllocatorDefault);
    if (!_client) {
        _failure = @"iOS did not allow this app to create a power-sensor client.";
    }
#endif
    return self;
}

- (void)dealloc {
    if (_client) {
        CFRelease(_client);
    }
    // Keep the framework loaded for the process lifetime, like the client.
}

- (BatterySensorReading *)readSensors {
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    NSMutableDictionary<NSString *, NSString *> *diagnostics = [NSMutableDictionary dictionary];
    diagnostics[@"IOHID read"] = @"read-only; one shared client";
    NSMutableDictionary<NSString *, id> *adapter = [NSMutableDictionary dictionary];
    CFDictionaryRef rawAdapter = _copyAdapter ? _copyAdapter() : NULL;
    diagnostics[@"Adapter read"] = !_copyAdapter ? @"API unavailable" :
        rawAdapter ? @"returned" : @"not returned";
    if (rawAdapter && CFGetTypeID(rawAdapter) == CFDictionaryGetTypeID()) {
        NSDictionary *properties = CFBridgingRelease(rawAdapter);
        // Adapter voltage/current describe the reported contract, not sensor measurements.
        // Do not copy names, serials, IDs, or the full negotiation dictionary.
        for (NSString *key in @[@"Watts", @"IsWireless", @"AdapterVoltage", @"Current"]) {
            if ([properties[key] isKindOfClass:[NSNumber class]]) {
                adapter[key] = properties[key];
            }
        }
    } else if (rawAdapter) {
        diagnostics[@"Adapter read"] = @"unexpected type rejected";
        CFRelease(rawAdapter);
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *sensors = [NSMutableArray array];
    [sensors addObjectsFromArray:[self readMatching:@{@"PrimaryUsagePage": @0xff08}
                                        eventType:25
                                      allowedNames:@[@"Charger VQ0u", @"Charger IQ0u"]
                                       diagnostics:diagnostics
                                             label:@"Power services"]];
    [sensors addObjectsFromArray:[self readMatching:@{@"PrimaryUsagePage": @0xff00, @"PrimaryUsage": @5}
                                        eventType:15
                                      allowedNames:@[@"gas gauge battery"]
                                       diagnostics:diagnostics
                                             label:@"Temperature services"]];
    NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - start;
    diagnostics[@"Read duration (s)"] = [NSString stringWithFormat:@"%.3f", duration];
    return [[BatterySensorReading alloc] initWithSensors:sensors
                                         adapterDetails:adapter
                                            diagnostics:diagnostics
                                               duration:duration];
}

- (NSArray<NSDictionary<NSString *, id> *> *)readMatching:(NSDictionary *)matching
                                             eventType:(uint32_t)eventType
                                          allowedNames:(NSArray<NSString *> *)allowedNames
                                           diagnostics:(NSMutableDictionary<NSString *, NSString *> *)diagnostics
                                                 label:(NSString *)label {
    _setMatching(_client, (__bridge CFDictionaryRef)matching);
    CFArrayRef rawServices = _copyServices(_client);
    if (!rawServices || CFGetTypeID(rawServices) != CFArrayGetTypeID()) {
        diagnostics[label] = @"not returned";
        if (rawServices) {
            CFRelease(rawServices);
        }
        return @[];
    }
    NSArray *services = CFBridgingRelease(rawServices);
    diagnostics[label] = [NSString stringWithFormat:@"%lu matched", (unsigned long)services.count];
    NSMutableArray<NSDictionary<NSString *, id> *> *readings = [NSMutableArray array];
    for (id service in services) {
        CFTypeRef ref = (__bridge CFTypeRef)service;
        CFTypeRef rawName = _copyProperty(ref, CFSTR("Product"));
        id name = rawName ? CFBridgingRelease(rawName) : nil;
        if (![name isKindOfClass:[NSString class]] || ![allowedNames containsObject:name]) {
            continue;
        }
        NSMutableDictionary<NSString *, id> *reading = [NSMutableDictionary dictionaryWithObject:name forKey:@"name"];
        for (NSString *key in @[@"PrimaryUsagePage", @"PrimaryUsage"]) {
            CFTypeRef rawValue = _copyProperty(ref, (__bridge CFStringRef)key);
            if (rawValue) {
                id value = CFBridgingRelease(rawValue);
                if ([value isKindOfClass:[NSNumber class]]) {
                    reading[key] = value;
                }
            }
        }
        CFTypeRef event = _copyEvent(ref, eventType, NULL, 0);
        if (event) {
            double value = _getFloat(event, eventType << 16);
            reading[@"status"] = isfinite(value) ? @"value returned" : @"nonfinite value rejected";
            if (isfinite(value)) {
                reading[@"value"] = @(value);
            }
            CFRelease(event);
        } else {
            reading[@"status"] = @"no event returned";
        }
        [readings addObject:reading];
    }
    return readings;
}

@end
