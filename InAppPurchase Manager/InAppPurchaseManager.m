//
//  Created by WhiteTiger on 6/1/13.
//  Copyright (c) 2013 WhiteTiger. All rights reserved.
//

#import "InAppPurchaseManager.h"

#import "NSData+Base64.h"

#pragma mark Define

/*
 * Macro di Debug
 */
#ifdef DEBUG
#define INAPPLog(_fmt_, ...)        NSLog(_fmt_, ##__VA_ARGS__)
#define INAPPFullLog(_fmt_, ...)    NSLog((@"%s [Line %d] " _fmt_), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define INAPPLog(...)
#define INAPPFullLog(...)
#endif

/*
 * Indirizzo del server di verifica
 */
#ifdef DEBUG
#define kVerifyReceipt @"https://sandbox.itunes.apple.com/verifyReceipt"
#else
#define kVerifyReceipt @"https://buy.itunes.apple.com/verifyReceipt"
#endif

#error Deve essere configurata la stringa di ShareSecret, per permettere la verifica lato Apple del prodotto acquistato
#define kShareSecret @""

/*
 * Messaggi
 */
#define kMessageOffPurchases        @"Acquisti disabilitati"
#define kMessageProductNotVerified  @"Prodotto non verificato"
#define kMessageNoProductsFound     @"Nessun prodotto trovato"
#define kMessageCancellation        @"Transazione annullata"

#pragma mark - Category: InAppPurchaseManager ()

@interface InAppPurchaseManager () <SKProductsRequestDelegate, SKPaymentTransactionObserver>

@end

#pragma mark

@implementation InAppPurchaseManager

- (id)init {
    if (self = [super init]) {
        self.hasShareSecret = YES;
    }
    
    return self;
}

- (void)dealloc {
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (BOOL)restoreCompletedTransactions {
    if ([SKPaymentQueue canMakePayments]) {
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmDisabled message:kMessageOffPurchases];
        }
        
        return NO;
    }
    
    return YES;
}

- (BOOL)getListOfProducts:(NSSet *)productIdentifiers {
    if (nil == productIdentifiers) {
        return NO;
        
    } else if ([SKPaymentQueue canMakePayments]) {
        SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:productIdentifiers];
        
        [request setDelegate:self];
        [request start];
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmDisabled message:kMessageOffPurchases];
        }
        
        return NO;
    }
    
    return YES;
}

- (BOOL)purchaseProduct:(SKProduct *)productIdentifier {
    if (nil == productIdentifier) {
        return NO;
        
    } else if ([SKPaymentQueue canMakePayments]) {
        SKPayment *payment = [SKPayment paymentWithProduct:productIdentifier];
        
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmDisabled message:kMessageOffPurchases];
        }
        
        return NO;
    }
    
    return YES;
}

/*
 * Metodi privati per il completamento delle transaction
 */

#pragma mark - Finish Transaction

- (void)_completeTransaction:(SKPaymentTransaction *)transaction {
    INAPPLog(@"\n");
    INAPPLog(@"## Purchased #########################################################");
    INAPPLog(@"transactionDate:         %@", transaction.transactionDate);
    INAPPLog(@"transactionIdentifier:   %@", transaction.transactionIdentifier);
    //INAPPLog(@"transactionReceipt:    %@", transaction.transactionReceipt);
    INAPPLog(@"transactionState:        %d", transaction.transactionState);
    INAPPLog(@"productIdentifier:       %@", transaction.payment.productIdentifier);
    INAPPLog(@"######################################################################");
    INAPPLog(@"\n");
    
    [self _verifyReceiptAndSecret:transaction];
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)_restoreTransaction:(SKPaymentTransaction *)transaction {
    if (transaction.transactionState == SKPaymentTransactionStateRestored && nil != transaction.originalTransaction) {
        INAPPLog(@"\n");
        INAPPLog(@"## Restored ##########################################################");
        INAPPLog(@"transactionDate:         %@", transaction.transactionDate);
        INAPPLog(@"transactionIdentifier:   %@", transaction.transactionIdentifier);
        //INAPPLog(@"transactionReceipt:    %@", transaction.transactionReceipt);
        INAPPLog(@"transactionState:        %d", transaction.transactionState);
        INAPPLog(@"productIdentifier:       %@", transaction.payment.productIdentifier);
        INAPPLog(@"######################################################################");
        INAPPLog(@"\n");
    }
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)_failedTransaction:(SKPaymentTransaction *)transaction {
    if ([[transaction error] code] != SKErrorPaymentCancelled) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [[transaction error] localizedDescription]]];
        }
        
        INAPPLog(@"\n");
        INAPPLog(@"## Failed ############################################################");
        INAPPLog(@"Message: %@", [[transaction error] localizedDescription]);
        INAPPLog(@"######################################################################");
        INAPPLog(@"\n");
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:kMessageCancellation];
        }
    }
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

/*
 * Metodi privati per la verifica del pagamento con i server Apple
 */

#pragma mark - VerifyReceipt / VerifyReceiptAndSecret

- (void)_verifyReceipt:(SKPaymentTransaction *)transaction {
    NSString *receiptDataAsString = [transaction.transactionReceipt base64EncodedString];
    NSError *error = nil;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kVerifyReceipt]];
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{ @"receipt-data" : receiptDataAsString }
                                                       options:kNilOptions
                                                         error:&error];
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
        }
        
        return;
    }
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    
    NSURLResponse *urlResponse = nil;
    
    NSData *dataResponse = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&error];
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
        }
        
        return;
    }
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:dataResponse
                                                         options:kNilOptions
                                                           error:&error];
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
        }
        
        return;
    }
    
    NSString *receiptStatus = [json valueForKey:@"status"];
    
    if (!receiptStatus || [receiptStatus intValue] != 0) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:kMessageProductNotVerified];
        }
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmSuccess:)]) {
            [self.delegate iapmSuccess:transaction];
        }
    }
}

- (void)_verifyReceiptAndSecret:(SKPaymentTransaction *)transaction {
    NSString *receiptDataAsString = [transaction.transactionReceipt base64EncodedString];
    NSError *error = nil;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kVerifyReceipt]];
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{ @"receipt-data" : receiptDataAsString, @"password" : kShareSecret }
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
        }
        
        return;
    }
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    
    NSURLResponse *urlResponse = nil;
    
    NSData *dataResponse = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&error];
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
        }
        
        return;
    }
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:dataResponse
                                                         options:kNilOptions
                                                           error:&error];
    
    if (error) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
        }
        
        return;
    }
    
    NSString *receiptStatus = [json valueForKey:@"status"];
    
    if (!receiptStatus || [receiptStatus intValue] != 0) {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmFailed message:kMessageProductNotVerified];
        }
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmSuccess:)]) {
            [self.delegate iapmSuccess:transaction];
        }
    }
}

#pragma mark - SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    NSArray *products = [response products];
    
    if ([products count] > 0) {
        if ([self.delegate respondsToSelector:@selector(iapmListOfProducts:)]) {
            [self.delegate iapmListOfProducts:products];
        }
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmEmpty message:kMessageNoProductsFound];
        }
    }
}

#pragma mark - SKRequestDelegate

- (void)requestDidFinish:(SKRequest *)request {
    request.delegate = nil;
    request = nil;
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    request.delegate = nil;
    request = nil;
    
    if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
        [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
    }
}

#pragma mark - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                [self _failedTransaction:transaction];
                
                break;
            }
                
            case SKPaymentTransactionStatePurchasing: {
                
                break;
            }
                
            case SKPaymentTransactionStatePurchased: {
                [self _completeTransaction:transaction];
                
                break;
            }
                
            case SKPaymentTransactionStateRestored: {
                [self _restoreTransaction:transaction];
                
                break;
            }
                
            default: {
                break;
            }
        }
        
        if ([self.delegate respondsToSelector:@selector(iapmStatus:)]) {
            [self.delegate iapmStatus:transaction.transactionState];
        }
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray *)transactions {
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    if ([[queue transactions] count] > 0) {
        NSArray *productIdentifiers = [[NSOrderedSet orderedSetWithArray:[[queue transactions] valueForKeyPath:@"payment.productIdentifier"]] array];
        
        for (NSString *productIdentifier in productIdentifiers) {
            NSArray *transactionCollections = [queue.transactions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"payment.productIdentifier == %@", productIdentifier]];
            
            transactionCollections = [transactionCollections sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                SKPaymentTransaction *objA = (SKPaymentTransaction *)obj1;
                SKPaymentTransaction *objB = (SKPaymentTransaction *)obj2;
                
                if ([objA.transactionDate compare:objB.transactionDate] == NSOrderedDescending) {
                    return YES;
                }
                
                return NO;
            }];
            
            if ([transactionCollections count] > 0) {
                if (self.enableVerify) {
                    if (self.hasShareSecret) {
                        [self _verifyReceiptAndSecret:[transactionCollections lastObject]];
                    } else {
                        [self _verifyReceipt:[transactionCollections lastObject]];
                    }
                } else {
                    if ([self.delegate respondsToSelector:@selector(iapmSuccess:)]) {
                        [self.delegate iapmSuccess:[transactionCollections lastObject]];
                    }
                }
            }
        }
        
    } else {
        if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
            [self.delegate iapmFailed:iapmEmpty message:kMessageNoProductsFound];
        }
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(iapmFailed:message:)]) {
        [self.delegate iapmFailed:iapmFailed message:[NSString stringWithFormat:@"%@", [error localizedDescription]]];
    }
}

@end
