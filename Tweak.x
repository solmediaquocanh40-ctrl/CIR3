#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

// ============================================================================
// CircleSwitcher v2.2.6 — Anti-Freeze 360° Infinite Carousel & Native Fullscreen Engine
// Supports iOS 14.0 - 16.3.1+ (Rootless & Rootful)
// Critical Stability Fixes (v2.2.6):
//   - REMOVED drawViewHierarchyInRect: (eliminates GPU/WindowServer deadlock on iOS 16)
//   - REMOVED viewDidLayoutSubviews mutation & recursive layoutSubviews loops
//   - NEVER activates mid-swipe (only activates after transitionDidEnd into mode 2)
//   - Home Bar pass-through in hitTest: (bottom 40pt ALWAYS goes to SpringBoard)
//   - Safe hardware UIBlurEffect entrance fade (zero private CAFilter lockups)
//   - 100% Native Fullscreen Apps (never touches SBAppSwitcherPageView in modes 0-3)
// ============================================================================

@interface SBAppSwitcherPageView : UIView
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGFloat cornerRadius;
- (void)_updateCornerRadius;
@end

@interface SBFluidSwitcherItemContainerHeaderView : UIView
@end

@interface SBFluidSwitcherItemContainer : UIView
@property (nonatomic, strong) SBAppSwitcherPageView *pageView;
@property (nonatomic, assign) CGFloat contentPageViewScale;
- (void)_cs_applyClassicTransform;
- (void)_cs_updateClassicTitleLabel:(UIView *)pageView;
- (void)_cs_resetToNativeFullscreen;
- (UIView *)_cs_findHeaderView;
- (void)_cs_restoreNativeHeader;
@end

@interface SBFluidSwitcherViewController : UIViewController
@property (nonatomic, copy) NSArray *appLayouts;
@property (nonatomic, strong) NSDictionary *visibleItemContainers;
- (void)_cs_handlePrefsOrStateChanged;
- (void)_cs_setSwitcherActive:(BOOL)active;
- (void)_cs_dismissSwitcherToHome;
- (void)_cs_scheduleExitWatchdog;
- (void)_cs_runExitGuardLoop;
- (void)_cs_exitGuardStepWithToken:(CFTimeInterval)token passesLeft:(NSInteger)passesLeft;
- (void)_cs_activateAppLayout:(id)appLayout bundleID:(NSString *)bundleID;
- (void)_cs_killAppLayout:(id)appLayout bundleID:(NSString *)bundleID;
@end

// ============================================================================
// Preferences State
// ============================================================================

static NSString * const kCSDomain = @"com.vn.circleswitcher";
static NSString * const kCSReloadNotification = @"com.vn.circleswitcher/ReloadPrefs";

static BOOL kEnabled = YES;
static NSInteger kLayoutMode = 0; // 0: Cylinder Cards, 1: Cylinder Orbs, 2: Orbital Orbs, 3: Radial Ring, 4-9: Classic
static BOOL kInfiniteScroll = YES;
static BOOL kCircleMorph = NO;
static CGFloat kCircleRadius = 34.0;
static CGFloat kWheelCurvature = 1.05;
static CGFloat kCardScale = 0.86;
static CGFloat kOrbSize = 0.72;
static CGFloat kCardSpacing = 1.05;

static NSInteger kTitlePosition = 1; // 0: Top, 1: Center (Dim), 2: Bottom, 3: Hidden
static CGFloat kCenterDimAlpha = 0.45;
static BOOL kShowCloseButton = YES;

static BOOL kLiquidGlass = YES;
static CGFloat kGlassRefract = 0.65;
static CGFloat kGlassSpecular = 0.85;
static CGFloat kGlassDispersion = 0.40;
static CGFloat kGlowIntensity = 0.65;
static NSInteger kGlowColorIndex = 0;
static NSString *kGlowColorHex = @"#00E5FF";

static BOOL kHologramBaseEnabled = YES;
static BOOL kBaseSyncColor = YES;
static NSString *kBaseColorHex = @"#00E5FF";
static CGFloat kBaseIntensity = 0.75;
static CGFloat kBaseScale = 1.0;
static BOOL kBackdropEnabled = YES;

static BOOL kMotionBlurOn = YES;
static CGFloat kMotionBlurIntensity = 7.5;
static BOOL kFadeIcons = YES;
static BOOL kScaleIcons = YES;
static BOOL kRollIcons = NO;
static BOOL kHapticFeedback = YES;

// Strictly controlled switcher state
static BOOL gSwitcherSettledOpen = NO;
static BOOL gIsUpdatingSwitcherState = NO;
static __weak SBFluidSwitcherViewController *gPrimarySwitcherVC = nil;
static __weak UIView *kLastCenteredContainer = nil;
static UIImpactFeedbackGenerator *kHapticGenerator = nil;

static const void *kCSCarouselStageKey = &kCSCarouselStageKey;
static const void *kCSHeaderViewKey = &kCSHeaderViewKey;
static const void *kCSHeaderOrigCenterKey = &kCSHeaderOrigCenterKey;
static const void *kCSClassicTitleLabelKey = &kCSClassicTitleLabelKey;
static CFTimeInterval kCSLastActivationTime = 0;
static CFTimeInterval kCSLastTransitionBeginTime = 0;
static CFTimeInterval kCSLastExitRequestTime = 0;
// 2.2.6 exit guard: YES from the moment an exit transition begins until it ends.
// While set, a repeating pass re-hides the native switcher views so iOS can never
// slip its own UI back under the overlay in the middle of an exit.
static BOOL gCSExitInProgress = NO;
static CFTimeInterval kCSExitGuardToken = 0;
static BOOL CSUsesInfiniteCarouselOverlay(void); // forward declaration (defined below)

// YES when the native per-card header must be forcibly hidden right now.
static BOOL CSShouldHideNativeHeader(void) {
    if (!kEnabled || !gSwitcherSettledOpen) return NO;
    // Overlay draws its own titles; classic (2.2.5+) also draws its own per-card labels,
    // so the native header is hidden in EVERY mode/position while the switcher is open.
    return YES;
}

// ============================================================================
// Color & Asset Helpers
// ============================================================================

static UIColor *CSColorFromHex(NSString *hexStr, CGFloat alpha) {
    if (!hexStr || ![hexStr isKindOfClass:[NSString class]] || hexStr.length == 0) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:alpha];
    }
    NSString *clean = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if ([clean hasPrefix:@"0X"]) clean = [clean substringFromIndex:2];
    if (clean.length != 6) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:alpha];
    }
    unsigned int rgbVal = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgbVal];
    CGFloat r = ((rgbVal & 0xFF0000) >> 16) / 255.0;
    CGFloat g = ((rgbVal & 0x00FF00) >> 8) / 255.0;
    CGFloat b = (rgbVal & 0x0000FF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

static UIColor *CSActiveGlowColor(CGFloat alpha) {
    if (kGlowColorHex && kGlowColorHex.length >= 6 && (kGlowColorIndex == 5 || ![kGlowColorHex isEqualToString:@"#00E5FF"])) {
        return CSColorFromHex(kGlowColorHex, alpha);
    }
    switch (kGlowColorIndex) {
        case 1:  return [UIColor colorWithRed:0.15 green:0.55 blue:1.00 alpha:alpha];
        case 2:  return [UIColor colorWithRed:0.68 green:0.35 blue:1.00 alpha:alpha];
        case 3:  return [UIColor colorWithRed:0.15 green:0.90 blue:0.65 alpha:alpha];
        case 4:  return [UIColor colorWithWhite:1.00 alpha:alpha];
        case 0:
        default: return [UIColor colorWithRed:0.00 green:0.90 blue:1.00 alpha:alpha];
    }
}

static UIColor *CSDispersedGlowColor(CGFloat alpha) {
    // Chromatic fringe approximation: shift the glow colour toward magenta by dispersion amount.
    UIColor *base = CSActiveGlowColor(1.0);
    CGFloat r=0,g=0,b=0,a=1;
    if (![base getRed:&r green:&g blue:&b alpha:&a]) { r=0; g=0.9; b=1.0; }
    CGFloat mixAmt = MIN(0.45, MAX(0.0, kGlassDispersion) * 0.45);
    r = r*(1.0-mixAmt) + 1.00*mixAmt;
    g = g*(1.0-mixAmt) + 0.25*mixAmt;
    b = b*(1.0-mixAmt) + 0.90*mixAmt;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

static UIColor *CSActiveBaseColor(CGFloat alpha) {
    if (kBaseSyncColor) return CSActiveGlowColor(alpha);
    return CSColorFromHex(kBaseColorHex, alpha);
}

static NSBundle *CSPrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = @[
            @"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle",
            @"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle"
        ];
        for (NSString *p in paths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                bundle = [NSBundle bundleWithPath:p];
                break;
            }
        }
    });
    return bundle;
}

static UIImage *CSLoadAsset(NSString *name, BOOL asTemplate) {
    static NSMutableDictionary<NSString *, UIImage *> *assetCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assetCache = [NSMutableDictionary dictionary];
    });
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%d", name, asTemplate ? 1 : 0];
    UIImage *cached = assetCache[cacheKey];
    if (cached) return cached;

    NSBundle *b = CSPrefsBundle();
    UIImage *img = b ? [UIImage imageNamed:name inBundle:b compatibleWithTraitCollection:nil] : nil;
    if (!img) {
        NSArray<NSString *> *paths = @[
            [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@3x.png", name],
            [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@2x.png", name],
            [NSString stringWithFormat:@"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@3x.png", name],
            [NSString stringWithFormat:@"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@2x.png", name]
        ];
        for (NSString *p in paths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                img = [UIImage imageWithContentsOfFile:p];
                if (img) break;
            }
        }
    }
    if (img && asTemplate) {
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (img) {
        assetCache[cacheKey] = img;
    }
    return img;
}

static BOOL CSUsesInfiniteCarouselOverlay(void) {
    return kEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
}

// ============================================================================
// Safe App Metadata Helpers (Zero drawViewHierarchyInRect -> Zero Deadlock!)
// ============================================================================

static NSString *CSBundleIDFromAppLayout(id appLayout) {
    if (!appLayout) return nil;
    @try {
        SEL itemRoleSel = NSSelectorFromString(@"itemForLayoutRole:");
        id displayItem = nil;
        if ([appLayout respondsToSelector:itemRoleSel]) {
            displayItem = ((id (*)(id, SEL, NSInteger))objc_msgSend)(appLayout, itemRoleSel, 1);
        }
        if (!displayItem && [appLayout respondsToSelector:NSSelectorFromString(@"allItems")]) {
            NSArray *items = ((id (*)(id, SEL))objc_msgSend)(appLayout, NSSelectorFromString(@"allItems"));
            displayItem = items.firstObject;
        }
        if (displayItem && [displayItem respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
            return ((id (*)(id, SEL))objc_msgSend)(displayItem, NSSelectorFromString(@"bundleIdentifier"));
        }
    } @catch (NSException *e) {}
    return nil;
}

static NSString *CSAppDisplayNameForBundleID(NSString *bundleID) {
    if (!bundleID || bundleID.length == 0) return @"App";
    @try {
        Class appCtrlCls = NSClassFromString(@"SBApplicationController");
        if (appCtrlCls && [appCtrlCls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ctrl = ((id (*)(id, SEL))objc_msgSend)(appCtrlCls, NSSelectorFromString(@"sharedInstance"));
            SEL appForBid = NSSelectorFromString(@"applicationWithBundleIdentifier:");
            if (ctrl && [ctrl respondsToSelector:appForBid]) {
                id app = ((id (*)(id, SEL, id))objc_msgSend)(ctrl, appForBid, bundleID);
                if (app && [app respondsToSelector:NSSelectorFromString(@"displayName")]) {
                    NSString *name = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"displayName"));
                    if (name.length > 0) return name;
                }
            }
        }
    } @catch (NSException *e) {}
    NSArray<NSString *> *parts = [bundleID componentsSeparatedByString:@"."];
    return parts.lastObject.length > 0 ? [parts.lastObject capitalizedString] : bundleID;
}

static UIImage *CSAppIconForBundleID(NSString *bundleID) {
    if (!bundleID || bundleID.length == 0) return nil;
    static NSMutableDictionary<NSString *, UIImage *> *iconCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iconCache = [NSMutableDictionary dictionary];
    });
    UIImage *cached = iconCache[bundleID];
    if (cached) return cached;

    @try {
        SEL iconSel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if ([UIImage respondsToSelector:iconSel]) {
            CGFloat scale = [UIScreen mainScreen].scale;
            UIImage *img = ((UIImage * (*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)([UIImage class], iconSel, bundleID, 2, scale);
            if (img) {
                iconCache[bundleID] = img;
                return img;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

// ============================================================================
// Preferences Loader
// ============================================================================

static NSDictionary *CSReadPreferencesDictionary(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kCSDomain];
    NSDictionary *dict = [defaults dictionaryRepresentation];
    if (dict && dict[@"enabled"] != nil) return dict;

    NSArray<NSString *> *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.vn.circleswitcher.plist",
        @"/var/mobile/Library/Preferences/com.vn.circleswitcher.plist"
    ];
    for (NSString *p in paths) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:p];
        if (plist) return plist;
    }
    return nil;
}

static void CSLoadPreferences(void) {
    NSDictionary *prefs = CSReadPreferencesDictionary();
    kEnabled             = prefs[@"enabled"]             ? [prefs[@"enabled"] boolValue]             : YES;
    kLayoutMode          = prefs[@"layoutMode"]          ? [prefs[@"layoutMode"] integerValue]       : 0;
    kInfiniteScroll      = prefs[@"infiniteScroll"]      ? [prefs[@"infiniteScroll"] boolValue]      : YES;
    kCircleMorph         = prefs[@"circleMorph"]         ? [prefs[@"circleMorph"] boolValue]         : NO;
    kCircleRadius        = prefs[@"circleRadius"]        ? [prefs[@"circleRadius"] doubleValue]      : 34.0;
    kWheelCurvature      = prefs[@"wheelCurvature"]      ? [prefs[@"wheelCurvature"] doubleValue]    : 1.05;
    kCardScale           = prefs[@"cardScale"]           ? [prefs[@"cardScale"] doubleValue]         : 0.86;
    kOrbSize             = prefs[@"orbSize"]             ? [prefs[@"orbSize"] doubleValue]           : 0.72;
    kCardSpacing         = prefs[@"cardSpacing"]         ? [prefs[@"cardSpacing"] doubleValue]       : 1.05;

    kTitlePosition       = prefs[@"titlePosition"]       ? [prefs[@"titlePosition"] integerValue]    : 1;
    kCenterDimAlpha      = prefs[@"centerDimAlpha"]      ? [prefs[@"centerDimAlpha"] doubleValue]    : 0.45;
    kShowCloseButton     = prefs[@"showCloseButton"]     ? [prefs[@"showCloseButton"] boolValue]     : YES;

    kLiquidGlass         = prefs[@"liquidGlass"]         ? [prefs[@"liquidGlass"] boolValue]         : YES;
    kGlassRefract        = prefs[@"glassRefract"]        ? [prefs[@"glassRefract"] doubleValue]      : 0.65;
    kGlassSpecular       = prefs[@"glassSpecular"]       ? [prefs[@"glassSpecular"] doubleValue]     : 0.85;
    kGlassDispersion     = prefs[@"glassDispersion"]     ? [prefs[@"glassDispersion"] doubleValue]     : 0.40;
    kGlowIntensity       = prefs[@"glowIntensity"]       ? [prefs[@"glowIntensity"] doubleValue]     : 0.65;
    kGlowColorIndex      = prefs[@"glowColorIndex"]      ? [prefs[@"glowColorIndex"] integerValue]   : 0;
    kGlowColorHex        = prefs[@"glowColorHex"]        ? [prefs[@"glowColorHex"] description]      : @"#00E5FF";

    kHologramBaseEnabled = prefs[@"hologramBaseEnabled"] ? [prefs[@"hologramBaseEnabled"] boolValue] : YES;
    kBaseSyncColor       = prefs[@"baseSyncColor"]       ? [prefs[@"baseSyncColor"] boolValue]       : YES;
    kBaseColorHex        = prefs[@"baseColorHex"]        ? [prefs[@"baseColorHex"] description]      : @"#00E5FF";
    kBaseIntensity       = prefs[@"baseIntensity"]       ? [prefs[@"baseIntensity"] doubleValue]     : 0.75;
    kBaseScale           = prefs[@"baseScale"]           ? [prefs[@"baseScale"] doubleValue]         : 1.0;
    kBackdropEnabled     = prefs[@"backdropEnabled"]     ? [prefs[@"backdropEnabled"] boolValue]     : YES;

    kMotionBlurOn        = prefs[@"motionBlurOn"]        ? [prefs[@"motionBlurOn"] boolValue]        : YES;
    kMotionBlurIntensity = prefs[@"motionBlurIntensity"] ? [prefs[@"motionBlurIntensity"] doubleValue]: 7.5;
    kFadeIcons           = prefs[@"fadeIcons"]           ? [prefs[@"fadeIcons"] boolValue]           : YES;
    kScaleIcons          = prefs[@"scaleIcons"]          ? [prefs[@"scaleIcons"] boolValue]          : YES;
    kRollIcons           = prefs[@"rollIcons"]           ? [prefs[@"rollIcons"] boolValue]           : NO;
    kHapticFeedback      = prefs[@"hapticFeedback"]      ? [prefs[@"hapticFeedback"] boolValue]      : YES;
}

static void CSReloadCallback(CFNotificationCenterRef center,
                             void *observer,
                             CFStringRef name,
                             const void *object,
                             CFDictionaryRef userInfo) {
    CSLoadPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gPrimarySwitcherVC) {
            [gPrimarySwitcherVC _cs_handlePrefsOrStateChanged];
        }
    });
}

// ============================================================================
// Frosted Liquid Glass Carousel Item View (Zero Squashing, 60fps Lightweight)
// ============================================================================

@interface CSInfiniteCarouselItem : UIView
@property (nonatomic, strong) id appLayout;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) UIImageView *ambientIconBG;
@property (nonatomic, strong) UIVisualEffectView *frostedGlassView;
@property (nonatomic, strong) UIView *dimOverlay;
@property (nonatomic, strong) UIImageView *glassRimOverlay;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *outerHaloView;
@property (nonatomic, assign) double lastTheta;
@property (nonatomic, assign) NSInteger lastBgAlphaBucket;
@end

@implementation CSInfiniteCarouselItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.12 blue:0.19 alpha:0.86];
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;

        // Soft tinted icon backdrop inside card/orb (hardware fast, matches approved glass UI)
        self.ambientIconBG = [[UIImageView alloc] initWithFrame:self.bounds];
        self.ambientIconBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ambientIconBG.contentMode = UIViewContentModeScaleAspectFill;
        self.ambientIconBG.alpha = 0.34;
        [self addSubview:self.ambientIconBG];

        UIBlurEffectStyle blurStyle = UIBlurEffectStyleDark;
        if (@available(iOS 13.0, *)) {
            blurStyle = UIBlurEffectStyleSystemUltraThinMaterialDark;
        }
        self.frostedGlassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
        self.frostedGlassView.frame = self.bounds;
        self.frostedGlassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.frostedGlassView];

        // Halo is a subview of the item itself: the item's masksToBounds clips it to the
        // item's own rounded shape, so one item's glow can never spill over a neighbour's border.
        self.outerHaloView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.outerHaloView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.outerHaloView.contentMode = UIViewContentModeScaleAspectFill;
        self.outerHaloView.userInteractionEnabled = NO;
        self.outerHaloView.alpha = 0.0;
        [self addSubview:self.outerHaloView];

        self.dimOverlay = [[UIView alloc] initWithFrame:self.bounds];
        self.dimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.dimOverlay.backgroundColor = [UIColor blackColor];
        self.dimOverlay.alpha = 0.0;
        [self addSubview:self.dimOverlay];

        self.glassRimOverlay = [[UIImageView alloc] initWithFrame:self.bounds];
        self.glassRimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.glassRimOverlay.contentMode = UIViewContentModeScaleToFill;
        self.glassRimOverlay.alpha = 0.0;
        [self addSubview:self.glassRimOverlay];

        self.iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 66, 66)];
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.iconImageView.layer.cornerRadius = 16.0;
        self.iconImageView.layer.masksToBounds = YES;
        [self addSubview:self.iconImageView];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.72;
        self.titleLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        self.titleLabel.layer.shadowOpacity = 0.80;
        self.titleLabel.layer.shadowRadius = 3.0;
        self.titleLabel.layer.shadowOffset = CGSizeMake(0, 1.5);
        [self addSubview:self.titleLabel];
    }
    return self;
}

@end

// ============================================================================
// Anti-Freeze 360° Infinite Carousel Stage View
// ============================================================================

@interface CSInfiniteCarouselStageView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SBFluidSwitcherViewController *ownerVC;
@property (nonatomic, strong) UIView *darkStageTint;
@property (nonatomic, strong) UIImageView *ambientBackdropView;
@property (nonatomic, strong) UIView *hologramBaseView;
@property (nonatomic, strong) UIImageView *baseOuterHalo;
@property (nonatomic, strong) UIImageView *baseInnerHalo;
@property (nonatomic, strong) UIView *baseGlowDisc;
@property (nonatomic, strong) UIView *baseRingView;
@property (nonatomic, strong) UIView *carouselContentLayer;
@property (nonatomic, strong) UIVisualEffectView *entranceBlurVeil;
@property (nonatomic, assign) CGPoint frontRestCenter;
@property (nonatomic, assign) CGSize frontRestSize;
@property (nonatomic, assign) CGFloat frontRestRadius;
@property (nonatomic, strong) UIView *entranceMorphView;
@property (nonatomic, strong) UIImageView *entranceMorphIcon;
@property (nonatomic, strong) UIVisualEffectView *entranceMorphBlur;
@property (nonatomic, strong) CADisplayLink *morphDisplayLink;
@property (nonatomic, assign) CFTimeInterval morphStartTime;
@property (nonatomic, assign) BOOL morphActive;
@property (nonatomic, strong) UIView *topHeaderPill;
@property (nonatomic, strong) UIImageView *topHeaderIcon;
@property (nonatomic, strong) UILabel *topHeaderLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSMutableArray<CSInfiniteCarouselItem *> *items;
@property (nonatomic, assign) double spinAngle;
@property (nonatomic, assign) double angularVelocity;
@property (nonatomic, assign) double snapTargetAngle;
@property (nonatomic, assign) BOOL isSnapping;
@property (nonatomic, assign) NSInteger frontItemIndex;
@property (nonatomic, assign) NSInteger lastHapticIndex;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CFTimeInterval lastTickTime;
@property (nonatomic, assign) BOOL panLockedVertical;
@property (nonatomic, assign) BOOL panLockedHorizontal;
@property (nonatomic, assign) CGFloat verticalDragOffset;
@property (nonatomic, assign) BOOL isLayingOutCarousel;
@property (nonatomic, assign) CGSize lastLayoutSize;
- (NSInteger)reloadAppsFromSwitcher;
- (CSInfiniteCarouselItem *)_cs_makeItemForLayout:(id)layout bundleID:(NSString *)bid halo:(UIImage *)haloImg rim:(UIImage *)rimImg stretchedRim:(UIImage *)stretchedRim;
- (void)layoutCarousel3D;
- (void)triggerSafeEntranceMotionBlur;
- (void)startEntranceMorph;
- (void)finishEntranceMorph;
- (void)stopPhysics;
- (void)startPhysicsIfNeeded;
@end

@implementation CSInfiniteCarouselStageView

- (instancetype)initWithFrame:(CGRect)frame owner:(SBFluidSwitcherViewController *)owner {
    self = [super initWithFrame:frame];
    if (self) {
        self.ownerVC = owner;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = YES; // starts hidden: _cs_setSwitcherActive reads wasHidden to run the entrance
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.items = [NSMutableArray array];
        self.frontItemIndex = 0;
        self.lastHapticIndex = -1;
        self.lastLayoutSize = CGSizeZero;

        self.darkStageTint = [[UIView alloc] initWithFrame:self.bounds];
        self.darkStageTint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.darkStageTint.backgroundColor = [UIColor colorWithRed:0.02 green:0.05 blue:0.10 alpha:0.42];
        self.darkStageTint.userInteractionEnabled = NO;
        [self addSubview:self.darkStageTint];

        self.ambientBackdropView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.ambientBackdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ambientBackdropView.image = CSLoadAsset(@"ambient_backdrop", YES);
        self.ambientBackdropView.contentMode = UIViewContentModeScaleAspectFill;
        self.ambientBackdropView.userInteractionEnabled = NO;
        [self addSubview:self.ambientBackdropView];

        self.hologramBaseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 320)];
        self.hologramBaseView.hidden = YES; // removed feature - see layoutCarousel3D
        self.hologramBaseView.userInteractionEnabled = NO;
        [self addSubview:self.hologramBaseView];

        UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
        self.baseOuterHalo = [[UIImageView alloc] initWithFrame:self.hologramBaseView.bounds];
        self.baseOuterHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseOuterHalo.image = haloImg;
        [self.hologramBaseView addSubview:self.baseOuterHalo];

        self.baseInnerHalo = [[UIImageView alloc] initWithFrame:CGRectInset(self.hologramBaseView.bounds, 48, 48)];
        self.baseInnerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseInnerHalo.image = haloImg;
        [self.hologramBaseView addSubview:self.baseInnerHalo];

        // Solid base layers: the real glow comes from a FILLED disc casting its own shadow
        // plus a solid ring stroke. The old design relied on the shadow of a transparent
        // container holding two faint template PNGs - a transparent view casts no usable
        // shadow, so the base vanished. These two views carry the glow by themselves.
        self.baseGlowDisc = [[UIView alloc] initWithFrame:self.hologramBaseView.bounds];
        self.baseGlowDisc.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseGlowDisc.userInteractionEnabled = NO;
        [self.hologramBaseView insertSubview:self.baseGlowDisc atIndex:0];

        self.baseRingView = [[UIView alloc] initWithFrame:CGRectInset(self.hologramBaseView.bounds, 10, 10)];
        self.baseRingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseRingView.userInteractionEnabled = NO;
        self.baseRingView.backgroundColor = [UIColor clearColor];
        [self.hologramBaseView addSubview:self.baseRingView];

        self.carouselContentLayer = [[UIView alloc] initWithFrame:self.bounds];
        self.carouselContentLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.carouselContentLayer.backgroundColor = [UIColor clearColor];
        [self addSubview:self.carouselContentLayer];

        // Hardware-safe blur veil for smooth entrance motion blur (never freezes CA!)
        self.entranceBlurVeil = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        self.entranceBlurVeil.frame = self.bounds;
        self.entranceBlurVeil.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.entranceBlurVeil.userInteractionEnabled = NO;
        self.entranceBlurVeil.alpha = 0.0;
        self.entranceBlurVeil.layer.zPosition = 850.0;
        [self addSubview:self.entranceBlurVeil];

        self.topHeaderPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 184, 42)];
        self.topHeaderPill.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.80];
        self.topHeaderPill.layer.cornerRadius = 21.0;
        self.topHeaderPill.layer.borderWidth = 1.0;
        self.topHeaderPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        self.topHeaderPill.userInteractionEnabled = NO;
        self.topHeaderPill.layer.zPosition = 900.0;
        [self addSubview:self.topHeaderPill];

        self.topHeaderIcon = [[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 28, 28)];
        self.topHeaderIcon.layer.cornerRadius = 7.0;
        self.topHeaderIcon.layer.masksToBounds = YES;
        [self.topHeaderPill addSubview:self.topHeaderIcon];

        self.topHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 6, 132, 30)];
        self.topHeaderLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        self.topHeaderLabel.textColor = [UIColor whiteColor];
        self.topHeaderLabel.textAlignment = NSTextAlignmentLeft;
        [self.topHeaderPill addSubview:self.topHeaderLabel];

        self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.closeButton.frame = CGRectMake(0, 0, 44, 44);
        self.closeButton.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.84];
        self.closeButton.layer.cornerRadius = 22.0;
        self.closeButton.layer.borderWidth = 1.25;
        self.closeButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        self.closeButton.layer.zPosition = 960.0;
        [self.closeButton addTarget:self action:@selector(handleCloseAllApps:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dealloc {
    [self stopPhysics];
}

// CRITICAL SAFETY: Always let Home Bar (bottom 44pt) & Status Bar (top 48pt) pass straight through to iOS!
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.05 || !self.userInteractionEnabled) {
        return nil;
    }
    CGFloat h = self.bounds.size.height;
    if (point.y > (h - 44.0) || point.y < 48.0) {
        return nil;
    }
    return [super hitTest:point withEvent:event];
}

- (void)stopPhysics {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.angularVelocity = 0.0;
    self.isSnapping = NO;
    [self finishEntranceMorph];
}

- (void)startPhysicsIfNeeded {
    if (!self.displayLink) {
        self.lastTickTime = CACurrentMediaTime();
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(physicsTick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (double)slotAngleForCount:(NSInteger)count {
    if (count <= 1) return 2.0 * M_PI;
    if (count <= 7) return (2.0 * M_PI) / (double)count;
    return (2.0 * M_PI) / 8.0;
}

- (void)triggerSafeEntranceMotionBlur {
    if (!kMotionBlurOn) return;

    self.carouselContentLayer.transform = CGAffineTransformMakeScale(1.03, 1.03);
    self.carouselContentLayer.alpha = 0.0;
    self.entranceBlurVeil.hidden = NO; // spin blur may have hidden it at alpha ~0
    self.entranceBlurVeil.alpha = MIN(0.45, MAX(0.10, kMotionBlurIntensity / 22.0));

    [UIView animateWithDuration:0.20 delay:0 usingSpringWithDamping:0.90 initialSpringVelocity:0.3 options:(UIViewAnimationOptions)UIViewAnimationOptionAllowUserInteraction animations:^{
        self.carouselContentLayer.transform = CGAffineTransformIdentity;
        self.carouselContentLayer.alpha = 1.0;
        self.entranceBlurVeil.alpha = 0.0;
    } completion:nil];
}

// ===== Entrance morph (user-approved concept, from his demo video) =====
// The front item starts as a big rounded "screen" and pulls its four corners in
// while shrinking into its carousel slot; a blur veil tracks the morph speed
// (strongest mid-flight, zero at both ends) so the open reads as ONE smooth
// motion instead of the old pop + one-frame jerk. The real carousel fades in
// underneath as the morph lands exactly on the front item's resting frame.
- (void)startEntranceMorph {
    if (self.morphActive || !kMotionBlurOn) return;
    if (!CSUsesInfiniteCarouselOverlay()) return;
    if (self.items.count == 0 || self.frontRestSize.width < 10.0) {
        [self layoutCarousel3D];
        if (self.items.count == 0 || self.frontRestSize.width < 10.0) return;
    }
    NSInteger idx = self.frontItemIndex;
    if (idx < 0 || idx >= (NSInteger)self.items.count) idx = 0;
    CSInfiniteCarouselItem *front = self.items[idx];
    UIImage *iconImg = front.iconImageView.image;
    if (!iconImg) return;

    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    UIView *morph = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w * 0.88, h * 0.82)];
    morph.center = CGPointMake(w * 0.5, h * 0.48);
    morph.backgroundColor = [UIColor clearColor];
    morph.clipsToBounds = YES;
    morph.layer.cornerRadius = 46.0;
    morph.layer.zPosition = 860.0;
    morph.userInteractionEnabled = NO;

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    glass.frame = morph.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.userInteractionEnabled = NO;
    [morph addSubview:glass];

    UIView *tint = [[UIView alloc] initWithFrame:morph.bounds];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tint.backgroundColor = [CSActiveGlowColor(1.0) colorWithAlphaComponent:0.16];
    tint.userInteractionEnabled = NO;
    [morph addSubview:tint];

    UIImageView *icon = [[UIImageView alloc] initWithImage:iconImg];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [morph addSubview:icon];
    self.entranceMorphIcon = icon;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
    blur.frame = morph.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.alpha = 0.0;
    blur.userInteractionEnabled = NO;
    [morph addSubview:blur];
    self.entranceMorphBlur = blur;

    [self addSubview:morph];
    self.entranceMorphView = morph;

    self.carouselContentLayer.alpha = 0.0;
    self.topHeaderPill.hidden = YES;

    self.morphActive = YES;
    self.morphStartTime = CACurrentMediaTime();
    self.morphDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(morphTick:)];
    [self.morphDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)morphTick:(CADisplayLink *)link {
    UIView *morph = self.entranceMorphView;
    if (!morph) { [self finishEntranceMorph]; return; }
    double p = (CACurrentMediaTime() - self.morphStartTime) / 0.55;
    if (p >= 1.0) { [self finishEntranceMorph]; return; }
    if (p < 0.0) p = 0.0;
    double e = (p < 0.5) ? (4.0 * p * p * p) : (1.0 - pow(-2.0 * p + 2.0, 3.0) / 2.0);

    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat startW = w * 0.88, startH = h * 0.82;
    CGPoint startC = CGPointMake(w * 0.5, h * 0.48);
    CGFloat gw = startW + (self.frontRestSize.width - startW) * (CGFloat)e;
    CGFloat gh = startH + (self.frontRestSize.height - startH) * (CGFloat)e;
    morph.bounds = CGRectMake(0, 0, gw, gh);
    morph.center = CGPointMake(startC.x + (self.frontRestCenter.x - startC.x) * (CGFloat)e,
                               startC.y + (self.frontRestCenter.y - startC.y) * (CGFloat)e);
    // Corners pull in as it shrinks: rounded rect -> the front item's own radius
    // (a full circle in the orb modes), exactly like the demo.
    morph.layer.cornerRadius = 46.0 + (self.frontRestRadius - 46.0) * (CGFloat)pow(e, 1.15);

    CGFloat iconSide = MIN(gw, gh) * (0.46 + (0.76 - 0.46) * (CGFloat)e);
    self.entranceMorphIcon.bounds = CGRectMake(0, 0, iconSide, iconSide);
    self.entranceMorphIcon.center = CGPointMake(gw * 0.5, gh * 0.5);

    // Motion blur follows speed: sin curve = calm at both ends, blurred mid-flight.
    self.entranceMorphBlur.alpha = (CGFloat)(sin(M_PI * p) * MIN(0.55, MAX(0.15, kMotionBlurIntensity / 16.0)));

    if (p > 0.62) {
        self.carouselContentLayer.alpha = MIN(1.0, (CGFloat)((p - 0.62) / 0.25));
        morph.alpha = 1.0 - MIN(1.0, MAX(0.0, (CGFloat)((p - 0.82) / 0.18)));
    }
}

- (void)finishEntranceMorph {
    if (!self.morphActive) return;
    self.morphActive = NO;
    [self.morphDisplayLink invalidate];
    self.morphDisplayLink = nil;
    [self.entranceMorphView removeFromSuperview];
    self.entranceMorphView = nil;
    self.entranceMorphIcon = nil;
    self.entranceMorphBlur = nil;
    self.carouselContentLayer.alpha = 1.0;
    if (!self.hidden) [self layoutCarousel3D];
}

// ===== Spin motion blur =====
// One stage-wide blur veil whose alpha tracks carousel speed: fast swipes get a
// light blur that masks frame steps; at rest it is fully gone and everything is
// crisp. A single extra view - no per-item filters - so it costs almost nothing.
- (void)_cs_updateSpinBlur:(CGFloat)target {
    UIVisualEffectView *veil = self.entranceBlurVeil;
    CGFloat next = veil.alpha + (target - veil.alpha) * 0.35;
    if (target <= 0.0 && next < 0.012) next = 0.0;
    veil.alpha = next;
    veil.hidden = next < 0.01;
}

- (CSInfiniteCarouselItem *)_cs_makeItemForLayout:(id)layout bundleID:(NSString *)bid halo:(UIImage *)haloImg rim:(UIImage *)rimImg stretchedRim:(UIImage *)stretchedRim {
    CSInfiniteCarouselItem *item = [[CSInfiniteCarouselItem alloc] initWithFrame:CGRectMake(0, 0, 180, 320)];
    item.appLayout = layout;
    item.bundleID = bid;
    item.displayName = CSAppDisplayNameForBundleID(bid);
    item.titleLabel.text = item.displayName;

    UIImage *appIcon = CSAppIconForBundleID(bid);
    item.iconImageView.image = appIcon;
    item.ambientIconBG.image = appIcon;

    BOOL isCircularMode = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
    item.glassRimOverlay.image = isCircularMode ? rimImg : stretchedRim;

    item.outerHaloView.image = haloImg;

    [self.carouselContentLayer addSubview:item];
    return item;
}

- (NSInteger)reloadAppsFromSwitcher {
    SBFluidSwitcherViewController *vc = self.ownerVC;
    if (!vc) return 0;

    NSArray *layouts = nil;
    @try {
        if ([vc respondsToSelector:@selector(appLayouts)]) {
            layouts = vc.appLayouts;
        }
        if ((!layouts || layouts.count == 0) && [vc respondsToSelector:NSSelectorFromString(@"dataSource")]) {
            id ds = ((id (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(@"dataSource"));
            SEL dsSel = NSSelectorFromString(@"appLayoutsForSwitcherContentController:");
            if (ds && [ds respondsToSelector:dsSel]) {
                layouts = ((id (*)(id, SEL, id))objc_msgSend)(ds, dsSel, vc);
            }
        }
        if (!layouts || layouts.count == 0) {
            for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
                Class cls = NSClassFromString(clsName);
                if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
                id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
                if (!inst) continue;
                id recent = nil;
                if ([inst respondsToSelector:NSSelectorFromString(@"recentAppLayouts")]) {
                    recent = ((id (*)(id, SEL))objc_msgSend)(inst, NSSelectorFromString(@"recentAppLayouts"));
                }
                if (recent && [recent respondsToSelector:NSSelectorFromString(@"recents")]) {
                    layouts = ((id (*)(id, SEL))objc_msgSend)(recent, NSSelectorFromString(@"recents"));
                    if (layouts.count > 0) break;
                }
            }
        }
    } @catch (NSException *e) {}

    // Build the incoming app list once (bundle IDs + layouts, capped at 24).
    NSMutableArray<NSString *> *newIDs = [NSMutableArray array];
    NSMutableArray *newLayouts = [NSMutableArray array];
    if ([layouts isKindOfClass:[NSArray class]]) {
        for (id layout in layouts) {
            NSString *bid = CSBundleIDFromAppLayout(layout);
            if (bid.length > 0) {
                [newIDs addObject:bid];
                [newLayouts addObject:layout];
                if (newIDs.count >= 24) break;
            }
        }
    }

    if (newIDs.count == 0) {
        for (CSInfiniteCarouselItem *item in self.items) {
            [item removeFromSuperview];
        }
        [self.items removeAllObjects];
        self.topHeaderPill.hidden = YES;
        self.closeButton.hidden = YES;
        return 0;
    }

    // Fast path: identical app set in identical order -> refresh layout references only.
    // Previously every state/prefs call rebuilt all items from scratch and reset the spin
    // angle to 0, which hitched the first frames of every open.
    if (self.items.count > 0 && newIDs.count == self.items.count) {
        BOOL sameOrder = YES;
        for (NSInteger i = 0; i < (NSInteger)newIDs.count; i++) {
            if (![newIDs[i] isEqualToString:self.items[i].bundleID]) { sameOrder = NO; break; }
        }
        if (sameOrder) {
            for (NSInteger i = 0; i < (NSInteger)newLayouts.count; i++) {
                self.items[i].appLayout = newLayouts[i];
            }
            [self layoutCarousel3D];
            return (NSInteger)self.items.count;
        }
    }

    UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
    UIImage *rimImg  = CSLoadAsset(@"glass_rim", NO);
    UIImage *stretchedRim = rimImg ? [rimImg resizableImageWithCapInsets:UIEdgeInsetsMake(rimImg.size.height * 0.45, rimImg.size.width * 0.45, rimImg.size.height * 0.45, rimImg.size.width * 0.45) resizingMode:UIImageResizingModeStretch] : nil;

    // 2.2.6 reuse path: opening an app reorders the recents, so the common case is
    // "same apps, new order" (plus the occasional kill/launch). The old code tore
    // down and rebuilt EVERY item on any difference - synchronously reloading every
    // icon - and reset the spin to zero. Now surviving apps keep their existing item
    // (icon, halo and rim already loaded); only departed apps are removed and only
    // genuinely new apps get a fresh item. spinAngle is preserved, and
    // layoutCarousel3D re-derives the front item from it, so the carousel never
    // jumps back to zero.
    if (self.items.count > 0) {
        NSMutableDictionary<NSString *, CSInfiniteCarouselItem *> *existingByID = [NSMutableDictionary dictionary];
        for (CSInfiniteCarouselItem *item in self.items) {
            if (item.bundleID.length > 0 && !existingByID[item.bundleID]) {
                existingByID[item.bundleID] = item;
            }
        }
        NSMutableSet<CSInfiniteCarouselItem *> *kept = [NSMutableSet set];
        NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:newIDs.count];
        BOOL anySurvivor = NO;
        for (NSInteger i = 0; i < (NSInteger)newIDs.count; i++) {
            CSInfiniteCarouselItem *item = existingByID[newIDs[i]];
            if (item) {
                item.appLayout = newLayouts[i];
                [kept addObject:item];
                [ordered addObject:item];
                anySurvivor = YES;
            } else {
                [ordered addObject:[NSNull null]];
            }
        }
        if (anySurvivor && [NSSet setWithArray:newIDs].count == newIDs.count) {
            for (CSInfiniteCarouselItem *item in self.items) {
                if (![kept containsObject:item]) [item removeFromSuperview];
            }
            for (NSInteger i = 0; i < (NSInteger)ordered.count; i++) {
                if (ordered[i] == [NSNull null]) {
                    ordered[i] = [self _cs_makeItemForLayout:newLayouts[i] bundleID:newIDs[i] halo:haloImg rim:rimImg stretchedRim:stretchedRim];
                }
            }
            [self.items removeAllObjects];
            [self.items addObjectsFromArray:ordered];
            [self layoutCarousel3D];
            return (NSInteger)self.items.count;
        }
    }

    // Full rebuild: no survivors (first open, or a completely different app set).
    for (CSInfiniteCarouselItem *item in self.items) {
        [item removeFromSuperview];
    }
    [self.items removeAllObjects];

    for (NSInteger idx = 0; idx < (NSInteger)newIDs.count; idx++) {
        CSInfiniteCarouselItem *item = [self _cs_makeItemForLayout:newLayouts[idx] bundleID:newIDs[idx] halo:haloImg rim:rimImg stretchedRim:stretchedRim];
        [self.items addObject:item];
    }

    self.spinAngle = 0.0;
    self.angularVelocity = 0.0;
    self.isSnapping = NO;
    self.verticalDragOffset = 0.0;
    self.frontItemIndex = 0;
    self.lastHapticIndex = 0;

    [self layoutCarousel3D];
    return (NSInteger)self.items.count;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(self.bounds.size, self.lastLayoutSize) && !self.hidden) {
        self.lastLayoutSize = self.bounds.size;
        [self layoutCarousel3D];
    }
}

- (void)layoutCarousel3D {
    if (self.isLayingOutCarousel) return;
    self.isLayingOutCarousel = YES;

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w < 10 || h < 10) {
        self.isLayingOutCarousel = NO;
        return;
    }

    UIColor *glowCol = CSActiveGlowColor(1.0);
    UIColor *baseCol = CSActiveBaseColor(1.0);

    self.ambientBackdropView.hidden = !kBackdropEnabled;
    self.ambientBackdropView.tintColor = [glowCol colorWithAlphaComponent:0.16 * MAX(0.25, kGlowIntensity)];

    // HOLOGRAM BASE REMOVED (user's order, 2026-11-18): the composite base with its
    // dark band / horizontal seam is gone for good - it is never shown in any mode.
    // The views still exist (harmless, always hidden) so no other code path changes.
    BOOL showBase = NO;
    self.hologramBaseView.hidden = YES;
    if (showBase) {
        CGFloat ringDim = MIN(w, h) * 0.84 * kBaseScale;
        self.hologramBaseView.layer.transform = CATransform3DIdentity;
        self.hologramBaseView.bounds = CGRectMake(0, 0, ringDim, ringDim);
        self.hologramBaseView.center = CGPointMake(w * 0.5, h * 0.72);

        self.baseOuterHalo.tintColor = baseCol;
        self.baseInnerHalo.tintColor = baseCol;
        self.hologramBaseView.alpha = MIN(1.0, kBaseIntensity * 1.1);

        CATransform3D baseTx = CATransform3DIdentity;
        baseTx.m34 = -1.0 / 520.0;
        baseTx = CATransform3DRotate(baseTx, 1.24, 1.0, 0.0, 0.0);
        self.hologramBaseView.layer.transform = baseTx;
        // No shadow on the transparent container itself (it produced a stray horizontal
        // shadow edge and no real glow). The filled disc below carries the glow instead.
        self.hologramBaseView.layer.shadowOpacity = 0.0;

        CGFloat halfDim = ringDim * 0.5;
        self.baseGlowDisc.bounds = CGRectMake(0, 0, ringDim, ringDim);
        self.baseGlowDisc.center = CGPointMake(halfDim, halfDim);
        self.baseGlowDisc.layer.cornerRadius = halfDim;
        self.baseGlowDisc.backgroundColor = [baseCol colorWithAlphaComponent:(0.10 + kBaseIntensity * 0.16)];
        self.baseGlowDisc.layer.shadowColor = baseCol.CGColor;
        self.baseGlowDisc.layer.shadowOpacity = (float)MIN(0.95, 0.35 + kBaseIntensity * 0.60);
        self.baseGlowDisc.layer.shadowRadius = 34.0;
        self.baseGlowDisc.layer.shadowOffset = CGSizeZero;

        CGFloat ringInset = ringDim * 0.06;
        self.baseRingView.bounds = CGRectMake(0, 0, ringDim - ringInset * 2.0, ringDim - ringInset * 2.0);
        self.baseRingView.center = CGPointMake(halfDim, halfDim);
        self.baseRingView.layer.cornerRadius = (ringDim - ringInset * 2.0) * 0.5;
        self.baseRingView.layer.borderWidth = 7.0;
        self.baseRingView.layer.borderColor = [baseCol colorWithAlphaComponent:MIN(0.95, 0.35 + kBaseIntensity * 0.55)].CGColor;
    }

    NSInteger count = (NSInteger)self.items.count;
    if (count == 0) {
        self.topHeaderPill.hidden = YES;
        self.closeButton.hidden = YES;
        self.isLayingOutCarousel = NO;
        return;
    }

    double slotAngle = [self slotAngleForCount:count];
    double totalSpan = (double)count * slotAngle;
    // Computed ONCE per layout pass: this colour was previously re-created for every
    // item on every frame of a drag - pure allocation churn on the main thread.
    UIColor *itemBorderColor = (kLiquidGlass && kGlowIntensity > 0.01) ? CSDispersedGlowColor(MIN(0.95, 0.45 + kGlowIntensity * 0.50)) : nil;

    NSInteger bestIdx = 0;
    double bestCos = -999.0;

    for (NSInteger i = 0; i < count; i++) {
        CSInfiniteCarouselItem *item = self.items[i];

        double raw = ((double)i * slotAngle) + self.spinAngle;
        double theta = raw;
        if (kInfiniteScroll && count > 1) {
            theta = fmod(raw + totalSpan * 0.5, totalSpan);
            if (theta < 0.0) theta += totalSpan;
            theta -= totalSpan * 0.5;
        }
        item.lastTheta = theta;

        // The old hard cut at |theta| > 0.96pi made the icon at the bottom of the radial
        // ring (theta = +/-pi, directly above the x button) vanish outright, and made
        // carousel icons pop instead of fading. Fade gradually instead, and never cull
        // in radial-ring mode, where the bottom slot is a real position.
        double absTheta = fabs(theta);
        double edgeFade = 1.0;
        if (kLayoutMode != 3) {
            const double fadeStart = M_PI * 0.86;
            const double fadeEnd = M_PI * 0.985;
            if (absTheta >= fadeEnd) {
                item.hidden = YES;
                item.outerHaloView.hidden = YES;
                continue;
            }
            if (absTheta > fadeStart) edgeFade = 1.0 - (absTheta - fadeStart) / (fadeEnd - fadeStart);
        }
        item.hidden = NO;

        double cosT = cos(theta);
        double sinT = sin(theta);
        double frontWeight = (cosT + 1.0) * 0.5;

        if (cosT > bestCos) {
            bestCos = cosT;
            bestIdx = i;
        }

        BOOL isCircular = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3 || kCircleMorph);
        CGFloat itemW = 196.0 * kCardScale;
        CGFloat itemH = 344.0 * kCardScale;

        if (kLayoutMode == 1) {
            CGFloat sz = 188.0 * kOrbSize;
            itemW = sz;
            itemH = sz;
        } else if (kLayoutMode == 2) {
            double focus = MAX(0.0, cosT);
            double focusSmooth = pow(focus, 3.0);
            // Cap the front orb by the angular spacing: with many apps the slots sit
            // close together and a full-size front orb swallows its neighbours.
            CGFloat bigOrb = MIN(224.0 * kCardScale, (CGFloat)((w * 0.46) * kCardSpacing * slotAngle * 1.30));
            CGFloat smallOrb = 112.0 * kOrbSize;
            CGFloat sz = smallOrb + (bigOrb - smallOrb) * focusSmooth;
            itemW = sz;
            itemH = sz;
        } else if (kLayoutMode == 3) {
            CGFloat sz = 118.0 * kOrbSize;
            itemW = sz;
            itemH = sz;
        }

        CGFloat posX = w * 0.5;
        CGFloat posY = h * 0.48;
        CGFloat transZ = 0.0;
        CGFloat angleY = 0.0;
        CGFloat depthScale = 1.0;

        if (kLayoutMode == 0 || kLayoutMode == 1) {
            CGFloat cylR = (w * 0.42) * kCardSpacing;
            posX = (w * 0.5) + cylR * sinT;
            posY = (h * 0.47) - (1.0 - cosT) * 24.0;
            transZ = (cosT - 1.0) * 185.0 * kWheelCurvature;
            angleY = -theta * 0.78 * kWheelCurvature;
            depthScale = 0.62 + 0.38 * frontWeight;
        } else if (kLayoutMode == 2) {
            CGFloat orbitR = (w * 0.46) * kCardSpacing;
            posX = (w * 0.5) + orbitR * sinT;
            posY = (h * 0.48) + (1.0 - cosT) * 18.0;
            transZ = (cosT - 1.0) * 145.0 * kWheelCurvature;
            angleY = -sinT * 0.52 * kWheelCurvature;
            depthScale = 0.72 + 0.28 * frontWeight;
        } else {
            CGFloat ringR = MIN(w, h) * 0.34 * kCardSpacing;
            posX = (w * 0.5) + ringR * sinT;
            posY = (h * 0.49) - ringR * cosT * 0.85;
            transZ = (cosT - 1.0) * 60.0;
            angleY = 0.0;
            depthScale = 0.76 + 0.24 * frontWeight;
        }

        CGFloat killYOffset = (i == self.frontItemIndex) ? self.verticalDragOffset : 0.0;
        posY += killYOffset;

        item.layer.transform = CATransform3DIdentity;
        item.bounds = CGRectMake(0, 0, itemW, itemH);
        item.center = CGPointMake(posX, posY);

        CGFloat cornerR = isCircular ? (itemW * 0.5) : MIN(itemW * 0.45, MAX(18.0, kCircleRadius));
        item.layer.cornerRadius = cornerR;
        if (@available(iOS 13.0, *)) {
            item.layer.cornerCurve = isCircular ? kCACornerCurveCircular : kCACornerCurveContinuous;
        }

        item.layer.zPosition = cosT * 520.0;
        CGFloat killAlpha = (killYOffset < -10.0) ? MAX(0.15, 1.0 + (killYOffset / 240.0)) : 1.0;
        CGFloat fadeAlpha = kFadeIcons ? MAX(0.32, 0.38 + 0.62 * frontWeight) : 0.94;
        item.alpha = fadeAlpha * killAlpha * (CGFloat)edgeFade;

        // Frosting for overlaps: the front item turns nearly opaque (its frosted glass
        // view blurs whatever sits behind it), so a neighbouring orb no longer ghosts
        // through it where the two overlap.
        CGFloat bgAlpha = 0.86 + 0.12 * (CGFloat)frontWeight;
        NSInteger bgBucket = (NSInteger)lround(bgAlpha * 24.0);
        if (bgBucket != item.lastBgAlphaBucket) {
            item.lastBgAlphaBucket = bgBucket;
            item.backgroundColor = [UIColor colorWithRed:0.08 green:0.12 blue:0.19 alpha:bgAlpha];
        }

        // Border and glass rim share the item's own layer path & corner radius, and the rim
        // image is refitted to the item's exact bounds on every layout - one frame, one shape.
        item.glassRimOverlay.frame = CGRectMake(0, 0, itemW, itemH);
        if (kLiquidGlass && kGlowIntensity > 0.01) {
            // ONE border at a time (user's order): only the front item wears the blue
            // border, fading in as it approaches the front. Side/back items are
            // borderless, so borders can never cross or stack on each other again.
            CGFloat borderWeight = MAX(0.0, MIN(1.0, ((CGFloat)frontWeight - 0.70) / 0.30));
            item.layer.borderWidth = 2.0 * borderWeight;
            item.layer.borderColor = [itemBorderColor colorWithAlphaComponent:itemBorderColor ? (CGColorGetAlpha(itemBorderColor.CGColor) * borderWeight) : 0.0].CGColor;
            // The rim PNG's stroke is inset from its canvas edges, so wherever it was
            // shown it drew a SECOND frame inside the layer border ('blue borders stack
            // on each other, glass does not fit the frame'). It is now never shown:
            // every item has exactly one frame - its layer border, same shape as its
            // clipped glass. (The glass sliders still drive border colour/dispersion,
            // halo and background frosting.)
            item.glassRimOverlay.alpha = 0.0;
        } else {
            item.layer.borderWidth = 0.0;
            item.glassRimOverlay.alpha = 0.0;
        }

        if (item.outerHaloView.image && kLiquidGlass && kGlowIntensity > 0.01 && isCircular) {
            item.outerHaloView.hidden = NO;
            item.outerHaloView.bounds = CGRectMake(0, 0, itemW * 1.12, itemH * 1.12);
            item.outerHaloView.center = CGPointMake(itemW * 0.5, itemH * 0.5);
            item.outerHaloView.tintColor = glowCol;
            item.outerHaloView.alpha = kGlowIntensity * MAX(0.25, frontWeight) * killAlpha * (0.55 + kGlassSpecular * 0.45);
        } else {
            item.outerHaloView.hidden = YES;
        }

        CGFloat iconSide = isCircular ? (itemW * 0.42) : (itemW * 0.36);
        item.iconImageView.bounds = CGRectMake(0, 0, iconSide, iconSide);
        item.iconImageView.layer.cornerRadius = iconSide * 0.23;

        if (kTitlePosition == 1) {
            item.dimOverlay.alpha = kCenterDimAlpha;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.44);
            item.titleLabel.bounds = CGRectMake(0, 0, itemW * 0.86, 24.0);
            item.titleLabel.center = CGPointMake(itemW * 0.5, itemH * 0.44 + iconSide * 0.5 + 16.0);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 1.0;
        } else if (kTitlePosition == 2) {
            item.dimOverlay.alpha = 0.16;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.52);
            item.titleLabel.bounds = CGRectMake(0, 0, itemW * 0.86, 22.0);
            item.titleLabel.center = CGPointMake(itemW * 0.5, itemH * 0.84);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 1.0;
        } else if (kTitlePosition == 0) {
            item.dimOverlay.alpha = 0.0;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.50);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 0.0;
        } else {
            item.dimOverlay.alpha = 0.0;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.50);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 0.0;
        }

        if (!kScaleIcons) depthScale = 1.0;
        CATransform3D tx = CATransform3DIdentity;
        tx.m34 = -1.0 / (880.0 / MAX(0.35, kWheelCurvature));
        tx = CATransform3DTranslate(tx, 0.0, 0.0, transZ);
        if (fabs(angleY) > 0.0001) {
            tx = CATransform3DRotate(tx, angleY, 0.0, 1.0, 0.0);
        }
        if (kRollIcons && fabs(theta) > 0.0001) {
            tx = CATransform3DRotate(tx, MAX(-0.35, MIN(0.35, -theta * 0.16)), 0.0, 0.0, 1.0);
        }
        tx = CATransform3DScale(tx, depthScale, depthScale, 1.0);
        item.layer.transform = tx;
    }

    self.frontItemIndex = bestIdx;

    if (kHapticFeedback && bestIdx != self.lastHapticIndex) {
        self.lastHapticIndex = bestIdx;
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        }
        [kHapticGenerator impactOccurred];
    }

    CSInfiniteCarouselItem *frontItem = self.items[bestIdx];
    if (frontItem) {
        // Resting frame of the front slot: the entrance morph lands exactly here.
        self.frontRestCenter = frontItem.center;
        self.frontRestSize = frontItem.bounds.size;
        self.frontRestRadius = frontItem.layer.cornerRadius;
    }
    if (kTitlePosition == 0 && frontItem) {
        self.topHeaderPill.hidden = NO;
        self.topHeaderIcon.image = frontItem.iconImageView.image;
        self.topHeaderLabel.text = frontItem.displayName;
        CGFloat pillY = (kLayoutMode == 0) ? (h * 0.16) : (h * 0.21);
        self.topHeaderPill.center = CGPointMake(w * 0.5, pillY);
    } else {
        self.topHeaderPill.hidden = YES;
    }

    self.closeButton.hidden = !kShowCloseButton;
    if (kShowCloseButton) {
        CGFloat closeY = (kLayoutMode == 0) ? (h * 0.72) : (h * 0.71);
        self.closeButton.center = CGPointMake(w * 0.5, closeY);
    }

    self.isLayingOutCarousel = NO;
}

- (void)physicsTick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    double dt = MIN(0.04, MAX(0.004, now - self.lastTickTime));
    self.lastTickTime = now;

    NSInteger count = (NSInteger)self.items.count;
    if (count == 0 || self.hidden) {
        [self stopPhysics];
        return;
    }

    [self _cs_updateSpinBlur:(kMotionBlurOn ? MIN(0.30, fabs(self.angularVelocity) * 0.030) : 0.0)];

    if (self.isSnapping) {
        double diff = self.snapTargetAngle - self.spinAngle;
        self.spinAngle += diff * MIN(1.0, dt * 14.0);
        if (fabs(diff) < 0.0015) {
            self.spinAngle = self.snapTargetAngle;
            self.isSnapping = NO;
            [self stopPhysics];
        }
        [self layoutCarousel3D];
        return;
    }

    if (fabs(self.angularVelocity) > 0.04) {
        self.spinAngle += self.angularVelocity * dt;
        self.angularVelocity *= pow(0.06, dt);
        [self layoutCarousel3D];
    } else {
        self.angularVelocity = 0.0;
        double step = [self slotAngleForCount:count];
        self.snapTargetAngle = round(self.spinAngle / step) * step;
        self.isSnapping = YES;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    CGPoint velocity = [pan velocityInView:self];

    if (pan.state == UIGestureRecognizerStateBegan) {
        [self finishEntranceMorph];
        [self stopPhysics];
        // Rasterize items for the duration of the drag: per-frame shadow/blur redraws on
        // the CPU were a major source of carousel stutter.
        for (CSInfiniteCarouselItem *item in self.items) {
            item.layer.shouldRasterize = YES;
            item.layer.rasterizationScale = [UIScreen mainScreen].scale;
        }
        self.panLockedHorizontal = NO;
        self.panLockedVertical = NO;
        self.verticalDragOffset = 0.0;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        if (!self.panLockedHorizontal && !self.panLockedVertical) {
            if (fabs(translation.y) > fabs(translation.x) * 1.4 && translation.y < -14.0) {
                self.panLockedVertical = YES;
            } else if (fabs(translation.x) > 8.0) {
                self.panLockedHorizontal = YES;
            }
            if (self.panLockedHorizontal || self.panLockedVertical) {
                // Discard the distance travelled before the lock was decided, otherwise the
                // first locked step applies the whole accumulated drag at once (visible jump).
                [pan setTranslation:CGPointZero inView:self];
                self.verticalDragOffset = 0.0;
                return;
            }
        }

        if (self.panLockedVertical) {
            self.verticalDragOffset = MIN(0.0, translation.y);
            [self layoutCarousel3D];
        } else {
            double deltaAngle = (double)translation.x / 185.0;
            self.spinAngle += deltaAngle;
            [pan setTranslation:CGPointZero inView:self];
            [self layoutCarousel3D];
            [self _cs_updateSpinBlur:(kMotionBlurOn ? MIN(0.30, fabs((double)velocity.x) / 210.0 * 0.030) : 0.0)];
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        for (CSInfiniteCarouselItem *item in self.items) item.layer.shouldRasterize = NO;
        if (self.panLockedVertical) {
            if (self.verticalDragOffset < -95.0 || velocity.y < -650.0) {
                [self handleKillFrontApp:nil];
            } else {
                self.verticalDragOffset = 0.0;
                [UIView animateWithDuration:0.25 animations:^{
                    [self layoutCarousel3D];
                }];
            }
            self.panLockedVertical = NO;
        } else {
            self.angularVelocity = MAX(-14.0, MIN(14.0, (double)velocity.x / 210.0));
            self.isSnapping = NO;
            [self startPhysicsIfNeeded];
            self.panLockedHorizontal = NO;
        }
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    CGPoint pt = [tap locationInView:self];

    if (!self.closeButton.hidden && CGRectContainsPoint(CGRectInset(self.closeButton.frame, -10, -10), pt)) {
        // The button's own action already fired for this touch; the stage tap gesture must
        // not fire a second close for the same tap.
        return;
    }

    NSArray<CSInfiniteCarouselItem *> *sorted = [self.items sortedArrayUsingComparator:^NSComparisonResult(CSInfiniteCarouselItem *a, CSInfiniteCarouselItem *b) {
        if (a.layer.zPosition > b.layer.zPosition) return NSOrderedAscending;
        if (a.layer.zPosition < b.layer.zPosition) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    CSInfiniteCarouselItem *hitItem = nil;
    for (CSInfiniteCarouselItem *item in sorted) {
        if (item.hidden || item.alpha < 0.1) continue;
        CALayer *pres = item.layer.presentationLayer ?: item.layer;
        CGRect frameInSelf = [self.carouselContentLayer convertRect:pres.frame toView:self];
        if (CGRectContainsPoint(frameInSelf, pt)) {
            hitItem = item;
            break;
        }
    }

    if (!hitItem) {
        [self.ownerVC _cs_dismissSwitcherToHome];
        return;
    }

    NSInteger idx = [self.items indexOfObject:hitItem];
    if (idx != NSNotFound && fabs(hitItem.lastTheta) > 0.42 && self.items.count > 1) {
        [self stopPhysics];
        double step = [self slotAngleForCount:self.items.count];
        double delta = -hitItem.lastTheta;
        self.snapTargetAngle = round((self.spinAngle + delta) / step) * step;
        self.isSnapping = YES;
        [self startPhysicsIfNeeded];
    } else {
        [self stopPhysics];
        [self.ownerVC _cs_activateAppLayout:hitItem.appLayout bundleID:hitItem.bundleID];
    }
}

- (void)handleKillFrontApp:(id)sender {
    if (self.items.count == 0 || self.frontItemIndex < 0 || self.frontItemIndex >= (NSInteger)self.items.count) return;

    CSInfiniteCarouselItem *target = self.items[self.frontItemIndex];
    id layoutToKill = target.appLayout;
    NSString *bidToKill = target.bundleID;

    if (kHapticFeedback) {
        UIImpactFeedbackGenerator *killGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [killGen impactOccurred];
    }

    [UIView animateWithDuration:0.22 animations:^{
        target.center = CGPointMake(target.center.x, -target.bounds.size.height);
        target.alpha = 0.0;
        target.outerHaloView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [target removeFromSuperview];
        [self.items removeObject:target];
        self.verticalDragOffset = 0.0;
        [self.ownerVC _cs_killAppLayout:layoutToKill bundleID:bidToKill];
        [UIView animateWithDuration:0.24 animations:^{
            [self layoutCarousel3D];
        }];
        // Contract: glide the survivors into their new, tighter slots and bring the next
        // app to the front. Without this they stayed parked at the old angles - the photo
        // with two icons stranded at opposite screen edges and the front slot empty.
        if (kLayoutMode != 3 && self.items.count > 1) {
            double step = [self slotAngleForCount:(NSInteger)self.items.count];
            if (step > 0.0001) {
                self.snapTargetAngle = round(self.spinAngle / step) * step;
                self.isSnapping = YES;
                [self startPhysicsIfNeeded];
            }
        }
    }];
}

// The x button closes EVERY app in the switcher (previously it only killed the centred
// app, which read as 'the x does not close everything'). Swipe-up on the front app
// still kills just that one app via handleKillFrontApp:.
- (void)handleCloseAllApps:(id)sender {
    if (self.items.count == 0) return;
    if (kHapticFeedback) {
        UIImpactFeedbackGenerator *killGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [killGen impactOccurred];
    }
    NSArray<CSInfiniteCarouselItem *> *allItems = [self.items copy];
    [self stopPhysics];
    [UIView animateWithDuration:0.22 animations:^{
        for (CSInfiniteCarouselItem *item in allItems) {
            item.center = CGPointMake(item.center.x, -item.bounds.size.height);
            item.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        for (CSInfiniteCarouselItem *item in allItems) {
            [item removeFromSuperview];
        }
        [self.items removeAllObjects];
        self.verticalDragOffset = 0.0;
        for (CSInfiniteCarouselItem *item in allItems) {
            [self.ownerVC _cs_killAppLayout:item.appLayout bundleID:item.bundleID];
        }
        [self layoutCarousel3D];
    }];
}

@end

static void CSSetNativeSwitcherViewsHidden(UIView *root, UIView *stage, BOOL hide) {
    for (UIView *sub in root.subviews) {
        if (sub == stage) continue;
        NSString *cls = NSStringFromClass([sub class]);
        if ([sub isKindOfClass:[UIScrollView class]] || [cls containsString:@"Scroll"]) {
            sub.alpha = hide ? 0.0 : 1.0;
        }
        if ([cls isEqualToString:@"SBFluidSwitcherItemContainerHeaderView"]) {
            sub.hidden = hide;
            sub.layer.opacity = hide ? 0.0 : 1.0;
        }
        CSSetNativeSwitcherViewsHidden(sub, stage, hide);
    }
}

// ============================================================================
// Hook SBFluidSwitcherItemContainerHeaderView
// ============================================================================

%hook SBFluidSwitcherItemContainerHeaderView

- (void)setAlpha:(CGFloat)alpha {
    if (CSShouldHideNativeHeader()) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}

// The old code ONLY intercepted setAlpha: - a header that was already visible when the
// switcher settled never got another setAlpha call, so it stayed stuck on screen forever.
// Hide proactively on every layout / window attach instead.
- (void)layoutSubviews {
    %orig;
    if (CSShouldHideNativeHeader()) {
        self.hidden = YES;
        self.layer.opacity = 0.0;
    }
}

- (void)didMoveToWindow {
    %orig;
    if (CSShouldHideNativeHeader()) {
        self.hidden = YES;
        self.layer.opacity = 0.0;
    }
}

%end

// ============================================================================
// Hook SBAppSwitcherPageView — 100% Untouched Fullscreen Apps!
// ============================================================================

%hook SBAppSwitcherPageView

- (void)layoutSubviews {
    %orig;

    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gSwitcherSettledOpen) {
        if (self.layer.borderWidth != 0.0 || self.layer.shadowOpacity != 0.0) {
            // Do NOT touch cornerRadius: it is the system's own card rounding. Zeroing it
            // made our border square while the snapshot stayed rounded - the black inner
            // frame in the user's photos.
            self.layer.masksToBounds = NO;
            self.layer.borderWidth = 0.0;
            self.layer.shadowOpacity = 0.0;
            self.layer.mask = nil;
        }
        return;
    }

    SBFluidSwitcherItemContainer *parentContainer = nil;
    UIView *sup = self.superview;
    while (sup) {
        if ([sup isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
            parentContainer = (SBFluidSwitcherItemContainer *)sup;
            break;
        }
        sup = sup.superview;
    }

    BOOL inSwitcherCard = (parentContainer != nil);
    if (inSwitcherCard && [parentContainer respondsToSelector:@selector(contentPageViewScale)]) {
        if (parentContainer.contentPageViewScale >= 0.90) {
            inSwitcherCard = NO;
        }
    }

    if (!inSwitcherCard) {
        self.layer.masksToBounds = NO;
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
        self.layer.mask = nil;
        return;
    }

    if (kCircleMorph) {
        CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
        self.layer.cornerRadius = MIN(minSide * 0.5, kCircleRadius);
        self.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    } else {
        // Keep the system's own card corner radius; clip + border live on THIS layer
        // only, so border, glass and mask share exactly one shape.
        if (self.layer.cornerRadius < 1.0) self.layer.cornerRadius = 28.0;
        self.layer.masksToBounds = YES;
    }

    if (kLiquidGlass && kGlowIntensity > 0.01) {
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = CSActiveGlowColor(MIN(0.95, 0.40 + kGlowIntensity * 0.55)).CGColor;
    } else {
        self.layer.borderWidth = 0.0;
    }
}

- (void)_updateCornerRadius {
    %orig;
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gSwitcherSettledOpen) {
        if (self.layer.borderWidth != 0.0) {
            self.layer.masksToBounds = NO;
            self.layer.borderWidth = 0.0;
            self.layer.mask = nil;
        }
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherItemContainer — Classic Modes (4..9) Only
// ============================================================================

%hook SBFluidSwitcherItemContainer

- (void)layoutSubviews {
    %orig;
    [self _cs_applyClassicTransform];
}

- (void)setCenter:(CGPoint)center {
    %orig;
    [self _cs_applyClassicTransform];
}

- (void)setContentPageViewScale:(CGFloat)scale {
    %orig(scale);
    [self _cs_applyClassicTransform];
}

%new
- (void)_cs_resetToNativeFullscreen {
    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (targetView) {
        if (!CATransform3DIsIdentity(targetView.layer.transform)) {
            targetView.layer.transform = CATransform3DIdentity;
        }
        if (targetView.layer.borderWidth != 0.0 || targetView.layer.shadowOpacity != 0.0) {
            targetView.layer.masksToBounds = NO;
            targetView.layer.borderWidth = 0.0;
            targetView.layer.shadowOpacity = 0.0;
            targetView.layer.mask = nil;
        }
    }
    if (self.layer.zPosition != 0.0) self.layer.zPosition = 0.0;
    if (self.layer.shadowOpacity != 0.0) self.layer.shadowOpacity = 0.0;
    self.layer.shadowPath = nil;
    UILabel *csTitleLabel = objc_getAssociatedObject(self, kCSClassicTitleLabelKey);
    if (csTitleLabel) csTitleLabel.hidden = YES;
    UIView *resetTarget = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (resetTarget && resetTarget.alpha != 1.0) resetTarget.alpha = 1.0;
    [self _cs_restoreNativeHeader];
}

%new
- (UIView *)_cs_findHeaderView {
    UIView *cached = objc_getAssociatedObject(self, kCSHeaderViewKey);
    if (cached) return cached;
    // Breadth-first search (depth <= 3) for this container's native header view.
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:self.subviews];
    NSInteger depth = 0;
    while (queue.count > 0 && depth < 3) {
        NSMutableArray<UIView *> *next = [NSMutableArray array];
        for (UIView *v in queue) {
            if ([NSStringFromClass([v class]) isEqualToString:@"SBFluidSwitcherItemContainerHeaderView"]) {
                objc_setAssociatedObject(self, kCSHeaderViewKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (!objc_getAssociatedObject(self, kCSHeaderOrigCenterKey)) {
                    objc_setAssociatedObject(self, kCSHeaderOrigCenterKey, [NSValue valueWithCGPoint:v.center], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                return v;
            }
            [next addObjectsFromArray:v.subviews];
        }
        queue = next;
        depth++;
    }
    return nil;
}

%new
- (void)_cs_restoreNativeHeader {
    UIView *header = [self _cs_findHeaderView];
    if (!header) return;
    header.layer.transform = CATransform3DIdentity;
    NSValue *orig = objc_getAssociatedObject(self, kCSHeaderOrigCenterKey);
    if (orig && header.superview == self) header.center = [orig CGPointValue];
    BOOL hide = CSShouldHideNativeHeader();
    header.hidden = hide;
    header.layer.opacity = hide ? 0.0 : 1.0;
}

%new
- (void)_cs_applyClassicTransform {
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gSwitcherSettledOpen) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    if ([self respondsToSelector:@selector(contentPageViewScale)] && self.contentPageViewScale >= 0.90) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (!targetView) return;

    UIWindow *win = self.window;
    CGFloat screenW = win ? win.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    if (screenW <= 0) screenW = 390.0;

    CGPoint centerInScreen = [self.superview convertPoint:self.center toView:win];
    CGFloat deltaX = centerInScreen.x - (screenW * 0.5);
    CGFloat t = (deltaX / (screenW * 0.54)) / MAX(0.45, kCardSpacing);
    CGFloat clampedT = MAX(-1.8, MIN(1.8, t));
    CGFloat absT = fabs(clampedT);

    if (kHapticFeedback && absT < 0.07 && kLastCenteredContainer != self) {
        kLastCenteredContainer = self;
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        }
        [kHapticGenerator impactOccurred];
    }

    self.layer.zPosition = 500.0 - (absT * 260.0);

    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = -1.0 / (900.0 / MAX(0.35, kWheelCurvature));

    CGFloat scale = kCardScale;
    CGFloat angleY = 0.0;
    CGFloat angleZ = 0.0;
    CGFloat transY = 0.0;
    CGFloat transZ = 0.0;

    switch (kLayoutMode) {
        case 4: {
            angleY = -clampedT * (M_PI / 5.2) * kWheelCurvature;
            angleZ = clampedT * (M_PI / 18.0) * kWheelCurvature;
            transY = (absT * absT) * 44.0 * kWheelCurvature;
            transZ = -absT * 95.0 * kWheelCurvature;
            scale  = kCardScale * MAX(0.78, 1.0 - absT * 0.10);
            break;
        }
        case 5: {
            angleY = -clampedT * (M_PI / 6.5) * kWheelCurvature;
            transZ = -absT * 60.0 * kWheelCurvature;
            scale  = kCardScale * MAX(0.78, 1.0 - absT * 0.09);
            break;
        }
        case 6: {
            angleY = -0.22 * kWheelCurvature;
            transZ = -absT * 110.0 * kWheelCurvature;
            transY = -absT * 14.0;
            scale  = kCardScale * MAX(0.74, 1.0 - absT * 0.11);
            break;
        }
        case 7: {
            CGFloat sign = (clampedT > 0) ? 1.0 : ((clampedT < 0) ? -1.0 : 0.0);
            CGFloat flowFactor = MIN(1.0, absT * 1.4);
            angleY = -sign * flowFactor * (M_PI / 3.4) * kWheelCurvature;
            transZ = -flowFactor * 120.0 * kWheelCurvature;
            scale  = kCardScale * (1.0 - flowFactor * 0.10);
            break;
        }
        case 8: {
            CGFloat sign = (clampedT > 0) ? 1.0 : ((clampedT < 0) ? -1.0 : 0.0);
            CGFloat flowFactor = MIN(1.0, absT * 1.4);
            angleY = sign * flowFactor * (M_PI / 3.4) * kWheelCurvature;
            transZ = -flowFactor * 120.0 * kWheelCurvature;
            scale  = kCardScale * (1.0 - flowFactor * 0.10);
            break;
        }
        case 9:
        default: {
            scale = kCardScale;
            break;
        }
    }

    if (!kScaleIcons) scale = kCardScale;
    if (kRollIcons) angleZ += clampedT * 0.06;

    transform = CATransform3DTranslate(transform, 0.0, transY, transZ);
    if (fabs(angleY) > 0.0001) {
        transform = CATransform3DRotate(transform, angleY, 0.0, 1.0, 0.0);
    }
    if (fabs(angleZ) > 0.0001) {
        transform = CATransform3DRotate(transform, angleZ, 0.0, 0.0, 1.0);
    }
    transform = CATransform3DScale(transform, scale, scale, 1.0);
    targetView.layer.transform = transform;
    targetView.alpha = kFadeIcons ? MAX(0.50, 1.0 - absT * 0.35) : 1.0;
    if (kTitlePosition == 1) targetView.alpha *= 0.78; // 'center (dim card)' behind our own title label

    // 2.2.5: repositioning the native header never survived the system's own layout
    // pass on device (headers stayed piled at the top in every classic mode, in the
    // user's 149s test video). The native header is now always hidden in classic too,
    // and CircleSwitcher draws its OWN title label inside the page view - it inherits
    // the card's transform exactly, so all 4 title positions work for real.
    UIView *header = [self _cs_findHeaderView];
    if (header) {
        header.hidden = YES;
        header.layer.opacity = 0.0;
    }
    [self _cs_updateClassicTitleLabel:targetView];

    if (kLiquidGlass && kGlowIntensity > 0.01) {
        // Glow hugs the card itself: the shadow path is the page view's rounded rect.
        // A plain container shadow used the container's bigger, offset frame and drew
        // the extra ghost frame around classic cards.
        CGFloat cardRadius = targetView.layer.cornerRadius;
        if (cardRadius < 1.0) cardRadius = 28.0;
        self.layer.shadowColor = CSActiveGlowColor(1.0).CGColor;
        self.layer.shadowOpacity = (float)(kGlowIntensity * MAX(0.25, 1.0 - absT * 0.45));
        self.layer.shadowRadius = 18.0;
        self.layer.shadowOffset = CGSizeMake(0, 6);
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:targetView.frame cornerRadius:cardRadius].CGPath;
    } else {
        self.layer.shadowOpacity = 0.0;
        self.layer.shadowPath = nil;
    }
}

%new
- (void)_cs_updateClassicTitleLabel:(UIView *)pageView {
    if (!pageView) return;
    UILabel *label = objc_getAssociatedObject(self, kCSClassicTitleLabelKey);
    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 1;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
        label.layer.shadowColor = [UIColor blackColor].CGColor;
        label.layer.shadowOpacity = 0.85;
        label.layer.shadowRadius = 3.0;
        label.layer.shadowOffset = CGSizeMake(0, 1.0);
        label.userInteractionEnabled = NO;
        objc_setAssociatedObject(self, kCSClassicTitleLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (label.superview != pageView) {
        [label removeFromSuperview];
        [pageView addSubview:label];
    }
    [pageView bringSubviewToFront:label];

    if (kTitlePosition == 3) { label.hidden = YES; return; }

    NSString *name = nil;
    @try {
        id layout = [self respondsToSelector:@selector(appLayout)] ? [self valueForKey:@"appLayout"] : nil;
        NSArray *allItems = [layout respondsToSelector:@selector(allItems)] ? [layout valueForKey:@"allItems"] : nil;
        id firstItem = [allItems isKindOfClass:[NSArray class]] ? allItems.firstObject : nil;
        NSString *bid = [firstItem respondsToSelector:@selector(bundleIdentifier)] ? [firstItem valueForKey:@"bundleIdentifier"] : nil;
        if (bid.length) {
            Class acCls = NSClassFromString(@"SBApplicationController");
            if (acCls && [acCls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
                id ac = ((id (*)(id, SEL))objc_msgSend)(acCls, NSSelectorFromString(@"sharedInstance"));
                SEL appSel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
                if (ac && [ac respondsToSelector:appSel]) {
                    id app = ((id (*)(id, SEL, id))objc_msgSend)(ac, appSel, bid);
                    if ([app respondsToSelector:@selector(displayName)]) name = [app valueForKey:@"displayName"];
                }
            }
            if (!name.length) name = [[bid componentsSeparatedByString:@"."] lastObject];
        }
    } @catch (NSException *e) {}
    if (!name.length) { label.hidden = YES; return; }
    if (![label.text isEqualToString:name]) label.text = name;
    label.hidden = NO;

    CGFloat pw = pageView.bounds.size.width;
    CGFloat ph = pageView.bounds.size.height;
    label.bounds = CGRectMake(0, 0, pw * 0.88, 22.0);
    if (kTitlePosition == 1) {
        label.center = CGPointMake(pw * 0.5, ph * 0.5);
    } else if (kTitlePosition == 2) {
        label.center = CGPointMake(pw * 0.5, ph - 20.0);
    } else {
        label.center = CGPointMake(pw * 0.5, 20.0);
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherViewController — Safe Non-Recursive Lifecycle
// ============================================================================

%hook SBFluidSwitcherViewController

- (void)viewDidLoad {
    %orig;
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    if (self.view.bounds.size.width >= screenW * 0.85 || !gPrimarySwitcherVC) {
        gPrimarySwitcherVC = self;
    }
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    if (self != gPrimarySwitcherVC && gPrimarySwitcherVC != nil) return;

    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            if (toMode == 2) {
                // Attach the overlay at the START of the open transition, not the end:
                // the stage rides the system's own presentation animation, so the first
                // visible frame is already CircleSwitcher - no default-switcher flash and
                // no 'overlay pops in after a delay'.
                kCSLastTransitionBeginTime = CACurrentMediaTime();
                gSwitcherSettledOpen = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self _cs_setSwitcherActive:YES];
                });
            } else if (toMode == 1 || toMode == 3) {
                // 2.2.6 exit guard: on some iOS builds the system re-shows / re-layouts
                // its native switcher views DURING the exit animation, which is how the
                // stock switcher kept leaking through even with teardown deferred to
                // DidEnd. Nothing is torn down here either - instead the native views
                // are re-hidden immediately (post-%orig) and a short loop keeps them
                // hidden until DidEnd, while the overlay rides out untouched on top.
                gCSExitInProgress = YES;
                CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
                if (stage && !stage.hidden) {
                    CSSetNativeSwitcherViewsHidden(self.view, stage, YES);
                    [self _cs_runExitGuardLoop];
                }
            }
            // Leaving the switcher (to Home=1 or App=3): do NOT tear anything down here.
            // Tearing down at transition BEGIN restored the native views for the entire
            // exit animation - the user tapped, CircleSwitcher vanished, and the DEFAULT
            // switcher rode the exit out. This was the #1 bug, and it survived earlier rounds
            // because this hook raced (and undid) the tap handler's own reordering.
            // Teardown is owned by transitionDidEnd below, when the switcher is already
            // off-screen.
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    if (self != gPrimarySwitcherVC && gPrimarySwitcherVC != nil) return;

    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            BOOL open = (toMode == 2);
            gSwitcherSettledOpen = open;
            gCSExitInProgress = NO; // any completed transition ends the exit guard
            // Activate asynchronously AFTER SpringBoard transition finishes -> ZERO mid-swipe hang!
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _cs_setSwitcherActive:open];
            });
        }
    } @catch (NSException *e) {}
}

%new
- (void)_cs_handlePrefsOrStateChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _cs_setSwitcherActive:gSwitcherSettledOpen];
    });
}

%new
- (void)_cs_setSwitcherActive:(BOOL)active {
    if (gIsUpdatingSwitcherState) return;
    gIsUpdatingSwitcherState = YES;

    CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);

    // Both the view-controller hook and the coordinator hook used to activate the stage for
    // the same transition, rebuilding the whole carousel twice per open. Debounce repeats.
    if (active && stage && !stage.hidden && (CACurrentMediaTime() - kCSLastActivationTime) < 1.0) {
        gIsUpdatingSwitcherState = NO;
        return;
    }

    if (active && CSUsesInfiniteCarouselOverlay()) {
        if (!stage) {
            stage = [[CSInfiniteCarouselStageView alloc] initWithFrame:self.view.bounds owner:self];
            [self.view addSubview:stage];
            objc_setAssociatedObject(self, kCSCarouselStageKey, stage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        stage.frame = self.view.bounds;
        NSInteger appCount = [stage reloadAppsFromSwitcher];

        if (appCount > 0) {
            // ONLY hide native switcher views when we actually have apps to display!
            CSSetNativeSwitcherViewsHidden(self.view, stage, YES);
            if (self.view.subviews.lastObject != stage) {
                [self.view bringSubviewToFront:stage];
            }
            BOOL wasHidden = stage.hidden;
            stage.hidden = NO;
            stage.alpha = 1.0;
            kCSLastActivationTime = CACurrentMediaTime();
            stage.userInteractionEnabled = YES;
            if (wasHidden) {
                if ((CACurrentMediaTime() - kCSLastTransitionBeginTime) <= 0.45) {
                    // Early attach (the normal open): run the entrance morph. It rides
                    // the system's own open animation - the front item shrinks from a
                    // big rounded screen into its slot with speed-tracked blur - so
                    // opening reads as one continuous motion instead of a pop + jerk.
                    // Self-gated on the Motion Blur preference inside the method.
                    [stage startEntranceMorph];
                } else {
                    // Late attach (prefs change or fallback path): no system animation
                    // left to ride, keep the older soft entrance.
                    [stage triggerSafeEntranceMotionBlur];
                }
            }
        } else {
            // Safety fallback: if 0 apps found, keep native switcher 100% visible & interactive!
            stage.hidden = YES;
            stage.userInteractionEnabled = NO;
            CSSetNativeSwitcherViewsHidden(self.view, stage, NO);
        }
    } else {
        if (stage) {
            [stage stopPhysics];
            stage.hidden = YES;
            stage.alpha = 0.0;
            stage.userInteractionEnabled = NO;
        }
        CSSetNativeSwitcherViewsHidden(self.view, stage, NO);
        for (UIView *sub in self.view.subviews) {
            for (UIView *child in sub.subviews) {
                if ([child isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
                    if (!active) {
                        [(SBFluidSwitcherItemContainer *)child _cs_resetToNativeFullscreen];
                    } else {
                        [(SBFluidSwitcherItemContainer *)child _cs_applyClassicTransform];
                    }
                }
            }
        }
    }

    gIsUpdatingSwitcherState = NO;
}

%new
- (void)_cs_runExitGuardLoop {
    CFTimeInterval token = CACurrentMediaTime();
    kCSExitGuardToken = token;
    [self _cs_exitGuardStepWithToken:token passesLeft:30];
}

%new
- (void)_cs_exitGuardStepWithToken:(CFTimeInterval)token passesLeft:(NSInteger)passesLeft {
    // ~40ms re-hide passes for the length of a typical exit (30 passes ≈ 1.2s cap,
    // so the loop can never outlive its transition even if DidEnd is somehow missed).
    if (!gCSExitInProgress || token != kCSExitGuardToken || passesLeft <= 0) return;
    CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
    if (stage && !stage.hidden) {
        CSSetNativeSwitcherViewsHidden(self.view, stage, YES);
        if (self.view.subviews.lastObject != stage) {
            [self.view bringSubviewToFront:stage];
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _cs_exitGuardStepWithToken:token passesLeft:passesLeft - 1];
    });
}

%new
- (void)_cs_dismissSwitcherToHome {
    gSwitcherSettledOpen = NO;

    // 2.2.5: send the 'go home' command FIRST and tear the overlay down afterwards.
    // The old order restored the native switcher first, so whenever the home command
    // was slow (or a selector missed on this iOS) the user landed on the DEFAULT
    // switcher instead of the home screen after tapping empty space.
    CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
    if (stage) {
        [stage stopPhysics];
        stage.userInteractionEnabled = NO;
    }

    BOOL sentHome = NO;
    @try {
        Class sbUI = NSClassFromString(@"SBUIController");
        if (sbUI && [sbUI respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ui = ((id (*)(id, SEL))objc_msgSend)(sbUI, NSSelectorFromString(@"sharedInstance"));
            for (NSString *selName in @[@"clickedMenuButton", @"handleHomeButtonSinglePressUp"]) {
                SEL homeSel = NSSelectorFromString(selName);
                if (ui && [ui respondsToSelector:homeSel]) {
                    ((void (*)(id, SEL))objc_msgSend)(ui, homeSel);
                    sentHome = YES;
                    break;
                }
            }
        }
        if (!sentHome) {
            for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
                Class cls = NSClassFromString(clsName);
                if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
                id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
                SEL toggleSel = NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:");
                if (inst && [inst respondsToSelector:toggleSel]) {
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(inst, toggleSel, 0);
                    sentHome = YES;
                    break;
                }
            }
        }
    } @catch (NSException *e) {}

    if (sentHome) {
        // Teardown is owned by the transition-DidEnd hook: the stage stays on top for
        // the whole exit animation and is hidden only once the switcher is off-screen.
        // (The 2.2.5 version tore down on a 0.30s timer here, which could also fire
        // after a fast re-open and kill the fresh stage.)
        [self _cs_scheduleExitWatchdog];
    } else {
        // 2.2.6: NEVER reveal the stock switcher as a fallback. The old code called
        // _cs_setSwitcherActive:NO here, restoring the native views on the spot - so
        // whenever every home selector missed on this iOS build, tapping empty space
        // swapped CircleSwitcher for the DEFAULT switcher. That was the #1 bug, by
        // design. The switcher is still open, so stay in it: hand the stage back
        // fully interactive, exactly as it was before the tap.
        gSwitcherSettledOpen = YES;
        if (stage && !stage.hidden) {
            stage.userInteractionEnabled = YES;
            [stage startPhysicsIfNeeded];
        }
    }
}

%new
- (void)_cs_scheduleExitWatchdog {
    kCSLastExitRequestTime = CACurrentMediaTime();
    CFTimeInterval token = kCSLastExitRequestTime;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (kCSLastExitRequestTime != token) return; // a newer exit/open superseded this one
        if (gCSExitInProgress) return;              // exit under way; DidEnd owns teardown
        if (!gSwitcherSettledOpen) return;           // the transition ran; DidEnd cleaned up
        // The exit never actually started (command swallowed): give the switcher back
        // instead of leaving a frozen (or faded-out, after a failed app activation)
        // overlay on screen.
        CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
        if (stage && !stage.hidden) {
            stage.userInteractionEnabled = YES;
            [stage startPhysicsIfNeeded];
            if (stage.alpha < 1.0) {
                [UIView animateWithDuration:0.15 animations:^{ stage.alpha = 1.0; }];
            }
        }
    });
}

%new
- (void)_cs_activateAppLayout:(id)appLayout bundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return;

    // Activate THROUGH the system in the SAME frame, and leave the overlay exactly as
    // it is. Restoring the native views here (the pre-2.2.5 behaviour) revealed the
    // default switcher for the whole exit animation - the user's #1 complaint. The
    // stage now rides the switcher view out, and the transition-DidEnd hook performs
    // the teardown once everything is off-screen.
    CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
    if (stage) {
        [stage stopPhysics];
        stage.userInteractionEnabled = NO;
    }
    [self _cs_scheduleExitWatchdog];

    BOOL activated = NO;
    @try {
        id app = nil;
        Class appCtrlCls = NSClassFromString(@"SBApplicationController");
        if (appCtrlCls && [appCtrlCls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ctrl = ((id (*)(id, SEL))objc_msgSend)(appCtrlCls, NSSelectorFromString(@"sharedInstance"));
            SEL appSel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
            if (ctrl && [ctrl respondsToSelector:appSel]) {
                app = ((id (*)(id, SEL, id))objc_msgSend)(ctrl, appSel, bundleID);
            }
        }
        Class uiCls = NSClassFromString(@"SBUIController");
        if (app && uiCls && [uiCls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ui = ((id (*)(id, SEL))objc_msgSend)(uiCls, NSSelectorFromString(@"sharedInstance"));
            SEL actSel = NSSelectorFromString(@"activateApplication:");
            if (ui && [ui respondsToSelector:actSel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(ui, actSel, app);
                activated = YES;
            }
        }
    } @catch (NSException *e) {}

    if (!activated) {
        @try {
            UIApplication *sbApp = [UIApplication sharedApplication];
            SEL launchSel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
            if ([sbApp respondsToSelector:launchSel]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(sbApp, launchSel, bundleID, NO);
            }
        } @catch (NSException *e) {}
    }

    // 2.2.6: fade the stage out over ~0.2s as the app takes over. Previously the
    // stage stayed frozen at full opacity for the entire exit and then vanished in
    // a single hard cut at transitionDidEnd - a visible jerk on every app open.
    // If the activation silently failed, no exit transition begins and the exit
    // watchdog restores the stage's alpha and interactivity instead (see
    // _cs_scheduleExitWatchdog), so the user is never stranded on a faded overlay.
    if (stage && !stage.hidden) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            stage.alpha = 0.0;
        } completion:nil];
    }
}

%new
- (void)_cs_killAppLayout:(id)appLayout bundleID:(NSString *)bundleID {
    if (!appLayout) return;
    @try {
        // ONE mechanism only - the first that applies. The old code fired the delegate kill,
        // the coordinator delete AND the recents remove together, double-deleting one layout.
        NSDictionary *vis = [self respondsToSelector:@selector(visibleItemContainers)] ? self.visibleItemContainers : nil;
        UIView *container = [vis isKindOfClass:[NSDictionary class]] ? vis[appLayout] : nil;
        if (container) {
            id del = [container valueForKey:@"_delegate"];
            SEL killContSel = NSSelectorFromString(@"killContainer:forReason:");
            if (del && [del respondsToSelector:killContSel]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(del, killContSel, container, 0);
                return;
            }
        }
        for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            if (!inst) continue;
            SEL delLayoutSel = NSSelectorFromString(@"_deleteAppLayout:forReason:");
            if ([inst respondsToSelector:delLayoutSel]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(inst, delLayoutSel, appLayout, 0);
                return;
            }
        }
        for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            if (!inst) continue;
            id recent = nil;
            if ([inst respondsToSelector:NSSelectorFromString(@"recentAppLayouts")]) {
                recent = ((id (*)(id, SEL))objc_msgSend)(inst, NSSelectorFromString(@"recentAppLayouts"));
            }
            SEL remSel = NSSelectorFromString(@"remove:");
            if (recent && [recent respondsToSelector:remSel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(recent, remSel, appLayout);
                return;
            }
        }
    } @catch (NSException *e) {}
}

%end

// ============================================================================
// Coordinator Backup Hooks (iOS 14-16.3.1+ Safe, Async Only)
// ============================================================================

%hook SBMainSwitcherControllerCoordinator

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    if (gPrimarySwitcherVC) return; // the VC hook already handles this transition - do not handle it twice
    // Exit teardown is owned by transitionDidEnd (see the VC hook): nothing to do at
    // Begin, so the overlay can never be stripped in the middle of an exit animation.
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    if (gPrimarySwitcherVC) return; // the VC hook already handles this transition - do not handle it twice
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gSwitcherSettledOpen = ([toModeObj integerValue] == 2);
            if (gPrimarySwitcherVC) [gPrimarySwitcherVC _cs_handlePrefsOrStateChanged];
        }
    } @catch (NSException *e) {}
}

%end

%ctor {
    @autoreleasepool {
        CSLoadPreferences();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            CSReloadCallback,
            (__bridge CFStringRef)kCSReloadNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
