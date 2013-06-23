//
//  Created by WhiteTiger on 6/1/13.
//  Copyright (c) 2013 WhiteTiger. All rights reserved.
//

/*
 * Note:
 *
 * Importare il framework "StoreKit.framework"
 */

#import <StoreKit/StoreKit.h>

typedef NS_ENUM(NSInteger, InAppPurchaseMessage) {
    iapmDisabled,
    iapmFailed,
    iapmEmpty
};

@protocol InAppPurchaseManagerDelegate <NSObject>

@required
- (void)iapmListOfProducts:(NSArray *)products;
- (void)iapmSuccess:(SKPaymentTransaction *)transaction;
- (void)iapmFailed:(InAppPurchaseMessage)type message:(NSString *)message;

@optional
- (void)iapmStatus:(SKPaymentTransactionState)status;

@end


@interface InAppPurchaseManager : NSObject

/*
 * Se impostato a YES, viene usato lo ShareSecret per le verifiche con il server (default: YES)
 */
@property (nonatomic, assign) BOOL hasShareSecret;

/*
 * Se impostato a YES, viene verificato il pagamento con i server Apple (default: NO)
 */
@property (nonatomic, assign) BOOL enableVerify;

@property (nonatomic, weak) id<InAppPurchaseManagerDelegate> delegate;

- (BOOL)restoreCompletedTransactions;
- (BOOL)getListOfProducts:(NSSet *)productIdentifiers;
- (BOOL)purchaseProduct:(SKProduct *)productIdentifier;

@end
