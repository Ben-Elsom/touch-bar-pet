// Private AppKit methods that let a background app put items on the
// Touch Bar's Control Strip and show a full-width "system modal" bar.
// Same approach as MTMR and Pock. Not public API, so a future macOS
// update could break it.
#import <AppKit/AppKit.h>

@interface NSTouchBarItem (TouchBarPetPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item NS_SWIFT_NAME(tbpAddSystemTrayItem(_:));
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item NS_SWIFT_NAME(tbpRemoveSystemTrayItem(_:));
@end

@interface NSTouchBar (TouchBarPetPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier
    NS_SWIFT_NAME(tbpPresentSystemModal(_:placement:systemTrayItemIdentifier:));
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar NS_SWIFT_NAME(tbpDismissSystemModal(_:));
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar NS_SWIFT_NAME(tbpMinimizeSystemModal(_:));
@end
