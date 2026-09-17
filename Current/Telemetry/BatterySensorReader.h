#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Only allowlisted sensor names, values and adapter fields leave the reader.
@interface BatterySensorReading : NSObject
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *sensors;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *adapterDetails;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *diagnostics;
@property(nonatomic, readonly) NSTimeInterval duration;
- (instancetype)initWithSensors:(NSArray<NSDictionary<NSString *, id> *> *)sensors
                 adapterDetails:(NSDictionary<NSString *, id> *)adapterDetails
                    diagnostics:(NSDictionary<NSString *, NSString *> *)diagnostics
                       duration:(NSTimeInterval)duration;
@end

/// Reuses one IOHID client for the process lifetime; all access is serialized.
/// Matches power/temperature services only. Never observes user input or writes hardware.
@interface BatterySensorReader : NSObject
+ (nullable BatterySensorReading *)readingWithError:
    (NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
