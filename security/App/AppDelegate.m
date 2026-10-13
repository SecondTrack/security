// Fenster und Navigation: die Startseite ist die Wurzel, Verbindungen liegen als Unterseite darüber.
// Hintergrund: offene Dialoge schließen (Passwort-Eingabe), beim Zurückkommen Zustand neu lesen.
#import "AppDelegate.h"
#import "HomeViewController.h"
#import "MeshTheme.h"
#import "MeshGuard.h"
#import "MeshNotifications.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Statusleiste ausblenden -> jede View ist volle 480 pt hoch, wie in Mesh.
    [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [MeshTheme bg];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[HomeViewController alloc] init]];
    nav.navigationBarHidden = YES;
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    [[MeshGuard shared] refresh];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshWillLockNotification object:nil];
    [self.window endEditing:YES];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [[MeshGuard shared] refresh];
}

@end
