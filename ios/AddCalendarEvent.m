#import "AddCalendarEvent.h"
#import "EKEventStoreSingleton.h"

@interface AddCalendarEvent()

@property (nonatomic) UIViewController *viewController;
@property (nonatomic) BOOL calendarAccessGranted;
@property (nonatomic) NSDictionary *eventOptions;

@property (nonatomic) RCTPromiseResolveBlock resolver;
@property (nonatomic) RCTPromiseRejectBlock rejecter;

@end


@implementation AddCalendarEvent

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

static NSString *const DELETED = @"DELETED";
static NSString *const SAVED = @"SAVED";
static NSString *const CANCELED = @"CANCELED";
static NSString *const DONE = @"DONE";
static NSString *const RESPONDED = @"RESPONDED";

- (NSDictionary *)constantsToExport
{
    return @{
             DELETED: DELETED,
             SAVED: SAVED,
             CANCELED: CANCELED,
             DONE: DONE,
             RESPONDED: RESPONDED
             };
}

static NSString *const _eventId = @"eventId";
static NSString *const _title = @"title";
static NSString *const _location = @"location";
static NSString *const _startDate = @"startDate";
static NSString *const _endDate = @"endDate";
static NSString *const _notes = @"notes";
static NSString *const _url = @"url";
static NSString *const _allDay = @"allDay";
static NSString *const _recurrence = @"recurrence";

static NSString *const MODULE_NAME= @"AddCalendarEvent";


- (EKEventStore *)getEventStoreInstance {
    return [EKEventStoreSingleton getInstance];
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        self.calendarAccessGranted = NO;
        [self resetPromises];
    }
    return self;
}

#pragma mark -
#pragma mark Calendar permission methods

RCT_EXPORT_METHOD(requestCalendarPermission:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    self.resolver = resolve;
    self.rejecter = reject;

    [self checkEventStoreAccessForCalendar];
}

- (void)checkEventStoreAccessForCalendar
{
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];

    switch (status)
    {
        case EKAuthorizationStatusAuthorized: [self markCalendarAccessAsGranted];
            break;
        case EKAuthorizationStatusNotDetermined: [self requestCalendarAccess];
            break;
        case EKAuthorizationStatusDenied:
        case EKAuthorizationStatusRestricted:
        {
            [self rejectCalendarPermission];
        }
            break;
        default:
            [self rejectCalendarPermission];
            break;
    }
}

- (void)markCalendarAccessAsGranted
{
    self.calendarAccessGranted = YES;
    [self resolvePromise: @(YES)];
}

- (void)rejectCalendarPermission
{
    [self resolvePromise: @(NO)];
}

- (void)requestCalendarAccess
{
    AddCalendarEvent * __weak weakSelf = self;
    [[self getEventStoreInstance] requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             if (granted) {
                 [weakSelf markCalendarAccessAsGranted];
             } else {
                 [weakSelf rejectCalendarPermission];
             }
         });
     }];
}

#pragma mark -
#pragma mark Dialog methods

RCT_EXPORT_METHOD(presentEventCreatingDialog:(NSDictionary *)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    self.eventOptions = options;
    self.resolver = resolve;
    self.rejecter = reject;


    void (^showEventCreatingController)(EKEvent *) = ^(EKEvent * event){
        EKEventEditViewController *controller = [[EKEventEditViewController alloc] init];
        controller.event = event;
        controller.eventStore = [self getEventStoreInstance];
        controller.editViewDelegate = self;
        [self assignNavbarColorsTo:controller.navigationBar];
        [self presentViewController:controller];
    };

    [self runIfAccessGranted:showEventCreatingController withEvent:[self createNewEventInstance]];
}

- (void)runIfAccessGranted: (void (^)(EKEvent *))codeBlock withEvent: (EKEvent *) event
{
    if (self.calendarAccessGranted && event) {
        codeBlock(event);
    } else if (self.calendarAccessGranted && !event) {
        NSString *evtId = self.eventOptions[_eventId];
        [self rejectPromise:@"eventNotFound" withMessage:[NSString stringWithFormat:@"event with id %@ not found", evtId] withError:nil];
    } else {
        [self rejectPromise:@"accessNotGranted" withMessage:@"accessNotGranted" withError:nil];
    }
}

RCT_EXPORT_METHOD(presentEventViewingDialog:(NSDictionary *)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    self.eventOptions = options;
    self.resolver = resolve;
    self.rejecter = reject;

    void (^showEventViewingController)(EKEvent *) = ^(EKEvent * event){
        EKEventViewController *controller = [[EKEventViewController alloc] init];
        controller.event = event;
        controller.delegate = self;
        if (options[@"allowsEditing"]) {
            controller.allowsEditing = [RCTConvert BOOL:options[@"allowsEditing"]];
        }
        if (options[@"allowsCalendarPreview"]) {
            controller.allowsCalendarPreview = [RCTConvert BOOL:options[@"allowsCalendarPreview"]];
        }

        UINavigationController *navBar = [[UINavigationController alloc] initWithRootViewController:controller];
        [self assignNavbarColorsTo:navBar.navigationBar];
        [self presentViewController:navBar];
    };

    [self runIfAccessGranted:showEventViewingController withEvent:[self getEditedEventInstance]];
}

-(void)assignNavbarColorsTo: (UINavigationBar *) navigationBar
{
    NSDictionary * navbarOptions = _eventOptions[@"navigationBarIOS"];

    if (navbarOptions) {
        if (navbarOptions[@"tintColor"]) {
            navigationBar.tintColor = [RCTConvert UIColor:navbarOptions[@"tintColor"]];
        }
        if (navbarOptions[@"backgroundColor"]) {
            navigationBar.backgroundColor = [RCTConvert UIColor:navbarOptions[@"backgroundColor"]];
        }
        if (navbarOptions[@"translucent"]) {
            navigationBar.translucent = [RCTConvert BOOL:navbarOptions[@"translucent"]];
        }
        if (navbarOptions[@"barTintColor"]) {
            navigationBar.barTintColor = [RCTConvert UIColor:navbarOptions[@"barTintColor"]];
        }
        if(navbarOptions[@"titleColor"]) {
            UIColor* titleColor = [RCTConvert UIColor:navbarOptions[@"titleColor"]];
            navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: titleColor};
        }
    }
}

RCT_EXPORT_METHOD(presentEventEditingDialog:(NSDictionary *)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    self.eventOptions = options;
    self.resolver = resolve;
    self.rejecter = reject;

    void (^showEventEditingController)(EKEvent *) = ^(EKEvent * event){
        EKEventEditViewController *controller = [[EKEventEditViewController alloc] init];
        controller.event = event;
        controller.eventStore = [self getEventStoreInstance];
        controller.editViewDelegate = self;
        [self assignNavbarColorsTo:controller.navigationBar];
        [self presentViewController:controller];
    };

    [self runIfAccessGranted:showEventEditingController withEvent:[self getEditedEventInstance]];
}

- (void)presentViewController: (UIViewController *) controller {
    self.viewController = RCTPresentedViewController();
    [self.viewController presentViewController:controller animated:YES completion:nil];
}

- (nullable EKEvent *)getEditedEventInstance {
    EKEvent *maybeEvent = [[self getEventStoreInstance] eventWithIdentifier: _eventOptions[_eventId]];
    if (!maybeEvent) {
        maybeEvent = [[self getEventStoreInstance] calendarItemWithIdentifier: _eventOptions[_eventId]];
    }
    return maybeEvent;
}

- (EKEvent *)createNewEventInstance {
    EKEvent *event = [EKEvent eventWithEventStore: [self getEventStoreInstance]];
    NSDictionary *options = _eventOptions;

    event.title = [RCTConvert NSString:options[_title]];
    event.location = options[_location] ? [RCTConvert NSString:options[_location]] : nil;

    if (options[_startDate]) {
        event.startDate = [RCTConvert NSDate:options[_startDate]];
    }
    if (options[_endDate]) {
        event.endDate = [RCTConvert NSDate:options[_endDate]];
    }
    if (options[_url]) {
        event.URL = [RCTConvert NSURL:options[_url]];
    }
    if (options[_notes]) {
        event.notes = [RCTConvert NSString:options[_notes]];
    }
    if (options[_allDay]) {
        event.allDay = [RCTConvert BOOL:options[_allDay]];
    }
    if (options[_recurrence]) {
        EKRecurrenceRule *rule = [self createRecurrenceRule:options[_recurrence] interval:0 occurrence:0 endDate:nil days: nil weekPositionInMonth: 0];
        if (rule) {
            event.recurrenceRules = [NSArray arrayWithObject:rule];
        }
    }
    return event;
}

- (void)rejectPromise: (NSString *) code withMessage: (NSString *) message withError: (NSError *) error {
    if (self.rejecter) {
        self.rejecter(code, message, error);
        [self resetPromises];
    }
}

- (void)resetPromises {
    self.resolver = nil;
    self.rejecter = nil;
}

#pragma mark -
#pragma mark EKEventEditViewDelegate

- (void)eventEditViewController:(EKEventEditViewController *)controller
          didCompleteWithAction:(EKEventEditViewAction)action
{
    AddCalendarEvent * __weak weakSelf = self;
    [self.viewController dismissViewControllerAnimated:YES completion:^
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             if (action == EKEventEditViewActionCanceled) {
                 [weakSelf resolveWithAction:CANCELED];
             } else if (action == EKEventEditViewActionSaved) {
                 EKEvent *evt = controller.event;
                 NSDictionary *params = @{
                                          @"eventIdentifier":evt.eventIdentifier,
                                          @"calendarItemIdentifier":evt.calendarItemIdentifier,
                                          };
                 [weakSelf resolveWithAction:SAVED andParams:params];
             } else if (action == EKEventEditViewActionDeleted) {
                 [weakSelf resolveWithAction:DELETED];
             }
         });
     }];
}


#pragma mark -
#pragma mark EKEventViewDelegate

- (void)eventViewController:(EKEventViewController *)controller
      didCompleteWithAction:(EKEventViewAction)action
{
    AddCalendarEvent * __weak weakSelf = self;
    [self.viewController dismissViewControllerAnimated:YES completion:^
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             if (action == EKEventViewActionDeleted) {
                 [weakSelf resolveWithAction:DELETED];
             } else if (action == EKEventViewActionDone) {
                 [weakSelf resolveWithAction:DONE];
             } else if (action == EKEventViewActionResponded) {
                 [weakSelf resolveWithAction:RESPONDED];
             }
         });
     }];
}

- (void)resolveWithAction: (NSString *)action {
    [self resolvePromise: @{
                             @"action": action
                             }];
}

- (void)resolveWithAction: (NSString *)action andParams: (NSDictionary *) params {
    NSMutableDictionary *extendedArgs = [params mutableCopy];
    [extendedArgs setObject:action forKey:@"action"];
    [self resolvePromise: extendedArgs];
}

- (void)resolvePromise: (id) result {
    if (self.resolver) {
        self.resolver(result);
        [self resetPromises];
    }
}

-(EKRecurrenceRule *)createRecurrenceRule:(NSString *)frequency interval:(NSInteger)interval occurrence:(NSInteger)occurrence endDate:(NSDate *)endDate days:(NSArray *)days weekPositionInMonth:(NSInteger) weekPositionInMonth
{
    EKRecurrenceRule *rule = nil;
    EKRecurrenceEnd *recurrenceEnd = nil;
    NSInteger recurrenceInterval = 1;
    NSArray *validFrequencyTypes = @[@"daily", @"weekly", @"monthly", @"yearly"];
    NSArray *daysOfTheWeekRecurrence = [self createRecurrenceDaysOfWeek:days];
    NSMutableArray *setPositions = nil;

    if (frequency && [validFrequencyTypes containsObject:frequency]) {

        if (endDate) {
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:endDate];
        } else if (occurrence && occurrence > 0) {
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:occurrence];
        }

        if (interval > 1) {
            recurrenceInterval = interval;
        }

        if (weekPositionInMonth > 0) {
            setPositions = [NSMutableArray array];
            [setPositions addObject:[NSNumber numberWithInteger: weekPositionInMonth ]];
        }
        rule = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:[self frequencyMatchingName:frequency]
                                                            interval:recurrenceInterval
                                                                 daysOfTheWeek:daysOfTheWeekRecurrence
                                                                 daysOfTheMonth:nil
                                                                 monthsOfTheYear:nil
                                                                 weeksOfTheYear:nil
                                                                 daysOfTheYear:nil
                                                                 setPositions:setPositions
                                                                 end:recurrenceEnd];
    }
    return rule;
}

-(NSMutableArray *) createRecurrenceDaysOfWeek: (NSArray *) days
{
    NSMutableArray *daysOfTheWeek = nil;

    if (days.count) {
        daysOfTheWeek = [[NSMutableArray alloc] init];

        for (NSString *day in days) {
            EKRecurrenceDayOfWeek *weekDay = [self dayOfTheWeekMatchingName: day];
            [daysOfTheWeek addObject:weekDay];

        }
    }

    return daysOfTheWeek;
}

-(EKRecurrenceDayOfWeek *) dayOfTheWeekMatchingName: (NSString *) day
{
    EKRecurrenceDayOfWeek *weekDay = nil;

    if ([day isEqualToString:@"MO"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:2];
    } else if ([day isEqualToString:@"TU"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:3];
    } else if ([day isEqualToString:@"WE"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:4];
    } else if ([day isEqualToString:@"TH"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:5];
    } else if ([day isEqualToString:@"FR"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:6];
    } else if ([day isEqualToString:@"SA"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:7];
    } else if ([day isEqualToString:@"SU"]) {
        weekDay = [EKRecurrenceDayOfWeek dayOfWeek:1];
    }

    NSLog(@"%s", "dayOfTheWeek");
    NSLog(@"%@", weekDay);
    return weekDay;
}

-(EKRecurrenceFrequency)frequencyMatchingName:(NSString *)name
{
    EKRecurrenceFrequency recurrence = nil;

    if ([name isEqualToString:@"weekly"]) {
        recurrence = EKRecurrenceFrequencyWeekly;
    } else if ([name isEqualToString:@"monthly"]) {
        recurrence = EKRecurrenceFrequencyMonthly;
    } else if ([name isEqualToString:@"yearly"]) {
        recurrence = EKRecurrenceFrequencyYearly;
    } else if ([name isEqualToString:@"daily"]) {
        recurrence = EKRecurrenceFrequencyDaily;
    }
    return recurrence;
}

@end
