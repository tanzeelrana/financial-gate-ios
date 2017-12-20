//
//  BROptionViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 6/11/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

// Updated by Farrukh Askari <farrukh.askari01@gmail.com> on 3:22 PM 17/4/17.

#import "BROptionViewController.h"
#import "BRRootViewController.h"
#import "BRSettingsViewController.h"
#import "BRTxDetailViewController.h"
#import "BRSeedViewController.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "UIImage+Utils.h"
#import "BREventConfirmView.h"
#import "BREventManager.h"
#import "FinancialGate-Swift.h"
#import <WebKit/WebKit.h>

#define TRANSACTION_CELL_HEIGHT 75

static NSString *dateFormat(NSString *template) {
    NSString *format = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];
    
    format = [format stringByReplacingOccurrencesOfString:@", " withString:@" "];
    format = [format stringByReplacingOccurrencesOfString:@" a" withString:@"a"];
    format = [format stringByReplacingOccurrencesOfString:@"hh" withString:@"h"];
    format = [format stringByReplacingOccurrencesOfString:@" ha" withString:@"@ha"];
    format = [format stringByReplacingOccurrencesOfString:@"HH" withString:@"H"];
    format = [format stringByReplacingOccurrencesOfString:@"H '" withString:@"H'"];
    format = [format stringByReplacingOccurrencesOfString:@"H " withString:@"H'h' "];
    format = [format stringByReplacingOccurrencesOfString:@"H" withString:@"H'h'"
              options:NSBackwardsSearch|NSAnchoredSearch range:NSMakeRange(0, format.length)];
    return format;
}

@interface BROptionViewController ()

@property (nonatomic, strong) IBOutlet UIView *logo;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *lock;

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, assign) BOOL moreTx;
@property (nonatomic, strong) NSMutableDictionary *txDates;
@property (nonatomic, strong) id backgroundObserver, balanceObserver, txStatusObserver;
@property (nonatomic, strong) id syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, strong) UIImageView *wallpaper;
@property (nonatomic, strong) BRWebViewController *buyController;

@end

@implementation BROptionViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.txDates = [NSMutableDictionary dictionary];
    self.wallpaper = [[UIImageView alloc] initWithFrame:self.navigationController.view.bounds];
    self.wallpaper.image = [UIImage imageNamed:@"wallpaper-default"];
    self.wallpaper.contentMode = UIViewContentModeBottomLeft;
    self.wallpaper.clipsToBounds = YES;
    self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2,
                                        self.navigationController.view.frame.size.height -
                                        self.wallpaper.frame.size.height/2);
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    self.navigationController.delegate = self;
    self.moreTx = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:animated];
    
    self.tableView.alpha = 1.0;
    self.navigationController.navigationItem.backBarButtonItem.enabled = YES;
    self.navigationController.navigationBar.tintColor = [UIColor lightGrayColor];
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
#if SNAPSHOT
    BRTransaction *tx = [[BRTransaction alloc] initWithInputHashes:@[uint256_obj(UINT256_ZERO)] inputIndexes:@[@(0)]
                         inputScripts:@[[NSData data]] outputAddresses:@[@""] outputAmounts:@[@(0)]];
    
    manager.localCurrencyCode = [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode];
    self.tableView.showsVerticalScrollIndicator = NO;
    self.moreTx = YES;
    manager.didAuthenticate = YES;
    [self unlock:nil];
    tx.txHash = UINT256_ZERO;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.transactions = @[tx, tx, tx, tx, tx, tx];
        [self.tableView reloadData];
        self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [manager stringForAmount:42980000],
                                     [manager localCurrencyStringForAmount:42980000]];
    });

    return;
#endif

    if (! manager.didAuthenticate) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.transactions = manager.wallet.allTransactions;
           
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        });
    }
    else [self unlock:nil];

    if (! self.backgroundObserver) {
        self.backgroundObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                self.moreTx = YES;
                self.transactions = manager.wallet.allTransactions;
                [self.tableView reloadData];
                self.navigationItem.titleView = self.logo;
                self.navigationItem.rightBarButtonItem = self.lock;
            }];
    }

    if (! self.balanceObserver) {
        self.balanceObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                BRTransaction *tx = self.transactions.firstObject;

                self.transactions = manager.wallet.allTransactions;

                if (! [self.navigationItem.title isEqual:NSLocalizedString(@"syncing...", nil)]) {
                    if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
                }

                if (self.transactions.firstObject != tx) {
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
                }
                else [self.tableView reloadData];
            }];
    }

    if (! self.txStatusObserver) {
        self.txStatusObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                self.transactions = manager.wallet.allTransactions;
                [self.tableView reloadData];
            }];
    }
    
    if (! self.syncStartedObserver) {
        self.syncStartedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncStartedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if ([[BRPeerManager sharedInstance]
                     timestampForBlockHeight:[BRPeerManager sharedInstance].lastBlockHeight] + 60*60*24*7 <
                    [NSDate timeIntervalSinceReferenceDate] &&
                    manager.seedCreationTime + 60*60*24 < [NSDate timeIntervalSinceReferenceDate]) {
                }
            }];
    }
    
    if (! self.syncFinishedObserver) {
        self.syncFinishedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
            }];
    }
    
    if (! self.syncFailedObserver) {
        self.syncFailedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
            }];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.buyController preload];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"has_alerted_buy_bitcoin"] == NO &&
        [WKWebView class] && [[BRAPIClient sharedClient] featureEnabled:BRFeatureFlagsBuyBitcoin]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"has_alerted_buy_bitcoin"];
        [self showBuyAlert];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        //BUG: XXX this isn't triggered from start/recover new wallet
        if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
        self.backgroundObserver = nil;
        if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
        self.balanceObserver = nil;
        if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
        self.txStatusObserver = nil;
        if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
        self.syncStartedObserver = nil;
        if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
        self.syncFinishedObserver = nil;
        if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
        self.syncFailedObserver = nil;
        self.wallpaper.clipsToBounds = YES;
        
        self.buyController = nil;
    }

    [super viewWillDisappear:animated];
}

- (void)dealloc {
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (BRWebViewController *)buyController {
    if (_buyController) {
        return _buyController;
    }
    if ([WKWebView class] && [[BRAPIClient sharedClient] featureEnabled:BRFeatureFlagsBuyBitcoin]) { // only available on iOS 8 and above
#if DEBUG || TESTFLIGHT
        _buyController = [[BRWebViewController alloc] initWithBundleName:@"bread-buy-staging" mountPoint:@"/buy"];
        //        self.buyController.debugEndpoint = @"http://localhost:8080";
#else
        _buyController = [[BRWebViewController alloc] initWithBundleName:@"bread-buy" mountPoint:@"/buy"];
#endif
        [_buyController startServer];
        [_buyController preload];
    }
    return _buyController;
}

- (uint32_t)blockHeight {
    static uint32_t height = 0;
    uint32_t h = [BRPeerManager sharedInstance].lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (void)setTransactions:(NSArray *)transactions {
    uint32_t height = self.blockHeight;

    if (! [BRWalletManager sharedInstance].didAuthenticate &&
        [self.navigationItem.title isEqual:NSLocalizedString(@"syncing...", nil)]) {
        _transactions = @[];
        if (transactions.count > 0) self.moreTx = YES;
    }
    else {
        if (transactions.count <= 5) self.moreTx = NO;
        _transactions = (self.moreTx) ? [transactions subarrayWithRange:NSMakeRange(0, 5)] : [transactions copy];
    
        if (! [BRWalletManager sharedInstance].didAuthenticate) {
            for (BRTransaction *tx in _transactions) {
                if (tx.blockHeight == TX_UNCONFIRMED ||
                    (tx.blockHeight > height - 5 && tx.blockHeight <= height)) continue;
                _transactions = [_transactions subarrayWithRange:NSMakeRange(0, [_transactions indexOfObject:tx])];
                self.moreTx = YES;
                break;
            }
        }
    }
}

- (void)setBackgroundForCell:(UITableViewCell *)cell tableView:(UITableView *)tableView indexPath:(NSIndexPath *)path {
    [cell viewWithTag:100].hidden = (path.row > 0);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:tableView numberOfRowsInSection:path.section]);
}

- (NSString *)dateForTx:(BRTransaction *)tx
{
    static NSDateFormatter *monthDayHourFormatter = nil;
    static NSDateFormatter *yearMonthDayHourFormatter = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{ // BUG: need to watch for NSCurrentLocaleDidChangeNotification
        monthDayHourFormatter = [NSDateFormatter new];
        monthDayHourFormatter.dateFormat = dateFormat(@"Mdja");
        yearMonthDayHourFormatter = [NSDateFormatter new];
        yearMonthDayHourFormatter.dateFormat = dateFormat(@"yyMdja");
    });
    
    NSString *date = self.txDates[uint256_obj(tx.txHash)];
    NSTimeInterval now = [[BRPeerManager sharedInstance] timestampForBlockHeight:TX_UNCONFIRMED];
    NSTimeInterval year = [NSDate timeIntervalSinceReferenceDate] - 364*24*60*60;

    if (date) return date;

    NSTimeInterval txTime = (tx.timestamp > 1) ? tx.timestamp : now;
    NSDateFormatter *desiredFormatter = (txTime > year) ? monthDayHourFormatter : yearMonthDayHourFormatter;
    
    date = [desiredFormatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:txTime]];
    date = [date stringByReplacingOccurrencesOfString:@"am" withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"pm" withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"AM" withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"PM" withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"a.m." withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"p.m." withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"A.M." withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"P.M." withString:@"p"];
    if (tx.blockHeight != TX_UNCONFIRMED) self.txDates[uint256_obj(tx.txHash)] = date;
    return date;
}

// MARK: - IBAction

- (IBAction)done:(id)sender
{
    [BREventManager saveEvent:@"tx_history:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)unlock:(id)sender {
    BRWalletManager *manager = [BRWalletManager sharedInstance];

    if (sender) [BREventManager saveEvent:@"tx_history:unlock"];
    //if (! manager.didAuthenticate && ! [manager authenticateWithPrompt:nil andTouchId:YES]) return;
    if (sender) [BREventManager saveEvent:@"tx_history:unlock_success"];
    
    [self.navigationItem setRightBarButtonItem:nil animated:(sender) ? YES : NO];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.transactions = manager.wallet.allTransactions;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sender && self.transactions.count > 0) {
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            else [self.tableView reloadData];
        });
    });
}

- (IBAction)scanQR:(id)sender {
    //TODO: show scanner in settings rather than dismissing
    [BREventManager saveEvent:@"tx_history:scan_qr"];
    UINavigationController *nav = (id)self.navigationController.presentingViewController;

    nav.view.alpha = 0.0;

    [nav dismissViewControllerAnimated:NO completion:^{
        [(id)((BRRootViewController *)nav.viewControllers.firstObject).sendViewController scanQR:nil];
        [UIView animateWithDuration:0.1 delay:1.5 options:0 animations:^{ nav.view.alpha = 1.0; } completion:nil];
    }];
}

- (void)showBuyAlert {
    // grab a blurred image for the background
    UIGraphicsBeginImageContext(self.navigationController.view.bounds.size);
    [self.navigationController.view drawViewHierarchyInRect:self.navigationController.view.bounds
                                         afterScreenUpdates:NO];
    UIImage *bgImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *blurredBgImg = [bgImg blurWithRadius:3];
    
    // display the popup
//    __weak BREventConfirmView *view =
//        [[NSBundle mainBundle] loadNibNamed:@"BREventConfirmView" owner:nil options:nil][0];
//    view.titleLabel.text = NSLocalizedString(@"Buy bitcoin in breadwallet!", nil);
//    view.descriptionLabel.text =
//        NSLocalizedString(@"You can now buy bitcoin in\nbreadwallet with cash or\nbank transfer.", nil);
//    [view.okBtn setTitle:NSLocalizedString(@"Try It!", nil) forState:UIControlStateNormal];
//    
//    view.image = blurredBgImg;
//    view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
//    view.frame = self.navigationController.view.bounds;
//    view.alpha = 0;
//    [self.navigationController.view addSubview:view];
//    
//    [UIView animateWithDuration:.5 animations:^{
//        view.alpha = 1;
//    }];
//    
//    view.completionHandler = ^(BOOL didApprove) {
//        if (didApprove) [self showBuy];
//        
//        [UIView animateWithDuration:.5 animations:^{
//            view.alpha = 0;
//        } completion:^(BOOL finished) {
//            [view removeFromSuperview];
//        }];
//    };
}

- (void)showBuy {
    [self presentViewController:self.buyController animated:YES completion:nil];
}

#pragma mark: - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 6;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *actionIdent = @"ActionCell", *disclosureIdent = @"DisclosureCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];

    switch (indexPath.row) {
        case 0:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Support", nil);
            break;
            
        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Transaction History", nil);
            break;
            
        case 2:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Apply For Debit Card", nil);
            cell.imageView.image = [UIImage imageNamed:@""];
            cell.accessoryType = UITableViewCellAccessoryNone;
            break;
            
        case 3:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Import Private Key", nil);
            break;
            
        case 4:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Settings", nil);
            break;

        case 5:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Markets", nil);
            break;
    }

    [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
    
    return cell;
}


#pragma mark: - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];

    if (sectionTitle.length == 0) return 22.0;

    CGRect r = [sectionTitle boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 20.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin
                attributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:13]} context:nil];
    
    return r.size.height + 22.0 + 10.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [UILabel new];
    CGRect r = CGRectMake(15.0, 0.0, v.frame.size.width - 20.0, v.frame.size.height - 22.0);
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont fontWithName:@"HelveticaNeue" size:13];
    l.textColor = [UIColor grayColor];
    l.shadowColor = [UIColor whiteColor];
    l.shadowOffset = CGSizeMake(0.0, 1.0);
    l.numberOfLines = 0;
    r.size.width = [l sizeThatFits:r.size].width;
    r.origin.x = (self.view.frame.size.width - r.size.width)/2;
    if (r.origin.x < 15.0) r.origin.x = 15.0;
    l.frame = r;
    v.backgroundColor = [UIColor clearColor];
    [v addSubview:l];

    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return (section + 1 == [self numberOfSectionsInTableView:tableView]) ? 22.0 : 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForFooterInSection:section])];
    v.backgroundColor = [UIColor clearColor];
    return v;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    UIViewController *destinationController = nil;
    
    self.tableView.alpha = 0.0;
    switch (indexPath.row) {
        case 0: // Support
        {
            [BREventManager saveEvent:@"tx_history:support"];
            destinationController = [self.storyboard instantiateViewControllerWithIdentifier:@"SupportViewController"];
            [self.navigationController pushViewController:destinationController animated:YES];
        }
            break;
            
        case 1: // Transaction History
        {
            [BREventManager saveEvent:@"tx_history:transaction_history"];
            destinationController = [self.storyboard instantiateViewControllerWithIdentifier:@"TxHistoryViewController"];
            [self.navigationController pushViewController:destinationController animated:YES];
        }
            
            break;
            
        case 2: // ApplyDebitCardCharge
        {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@""
                                         message:NSLocalizedString(@"Coming soon...", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* yesButton = [UIAlertAction
                                        actionWithTitle:NSLocalizedString(@"ok", nil)
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction * action) {
                                            [alert dismissViewControllerAnimated:YES completion:nil];
                                        }];
            
            [alert addAction:yesButton];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
            break;
        case 3: // Import Private Key
        {
            [BREventManager saveEvent:@"tx_history:import_priv_key"];
            [self scanQR:nil];
        }
            break;
        case 4: // Settings
        {
            [BREventManager saveEvent:@"tx_history:settings"];
            destinationController = [self.storyboard instantiateViewControllerWithIdentifier:@"SettingsViewController"];
            [self.navigationController pushViewController:destinationController animated:YES];
        }
            break;
        case 5: // Markets
        {
            [BREventManager saveEvent:@"markets:markets"];
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MarketsViewStoryboard"
                                                                 bundle:nil];
            destinationController = [storyboard instantiateViewControllerWithIdentifier:@"BRMarketsViewController"];
            [self.navigationController pushViewController:destinationController animated:YES];
        }
            break;
        default:
            break;
    }
}

#pragma mark: - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
        return;
    }

    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"show", nil)]) {
        BRSeedViewController *seedController =
            [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
    
        if (seedController.authSuccess) [self.navigationController pushViewController:seedController animated:YES];
    }    
}

#pragma mark: - UIViewControllerAnimatedTransitioning

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *containerView = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    BOOL pop = (to == self || (from != self && [to isKindOfClass:[BRSettingsViewController class]])) ? YES : NO;

    if (self.wallpaper.superview != containerView) [containerView insertSubview:self.wallpaper belowSubview:from.view];
    self.wallpaper.clipsToBounds = NO;
    to.view.center = CGPointMake(containerView.frame.size.width*(pop ? -1 : 3)/2, to.view.center.y);
    [containerView addSubview:to.view];

    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
    initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        to.view.center = from.view.center;
        from.view.center = CGPointMake(containerView.frame.size.width*(pop ? 3 : -1)/2, from.view.center.y);
        self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 -
                                            containerView.frame.size.width*(pop ? 0 : 1)*PARALAX_RATIO,
                                            self.wallpaper.center.y);
    } completion:^(BOOL finished) {
        if (pop) [from.view removeFromSuperview];
        [transitionContext completeTransition:YES];
    }];
}

#pragma mark: - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                  animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
                                                 toViewController:(UIViewController *)toVC {
    return self;
}

#pragma mark: - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed{
    return self;
}

@end
