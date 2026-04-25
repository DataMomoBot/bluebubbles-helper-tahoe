//
//  NetworkController.m
//  BlueBubblesHelper
//
//  Created by Samer Shihabi on 11/20/20.
//  Copyright © 2020 BlueBubbleMessaging. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NetworkController.h"
#import "GCDAsyncSocket.h"
#import "Logging.h"

@implementation NetworkController

@synthesize messageReceivedBlock;


#pragma mark - Singleton

static id sharedInstance = nil;

+ (void)initialize {
  if (self == [NetworkController class]) {
    sharedInstance = [[self alloc] init];
  }
}

+ (NetworkController*)sharedInstance {
  return sharedInstance;
}


#pragma mark - Public methods

#define CLAMP(x, low, high) ({\
  __typeof__(x) __x = (x); \
  __typeof__(low) __low = (low);\
  __typeof__(high) __high = (high);\
  __x > __high ? __high : (__x < __low ? __low : __x);\
  })

- (void)connect {
    // Tahoe fix: BlueBubbles listens on IPv6 [::1]:45670. "localhost" can be flaky on newer macOS.
    // Try ::1 first, then fall back to 127.0.0.1. Add extra logging for debugging.
    int port = CLAMP(45670 + getuid()-501, 45670, 65535);
    DLog("BLUEBUBBLESHELPER[Tahoe]: Connecting to socket on port %{public}d (macOS Tahoe build)", port);

    if (asyncSocket != nil) {
        [asyncSocket disconnect];
        asyncSocket = nil;
    }

    NSError *err = nil;
    NSString *host = @"::1";
    asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];

    if (![asyncSocket connectToHost:host onPort:port error:&err]) {
        DLog("BLUEBUBBLESHELPER[Tahoe]: Failed to connect to IPv6 ::1:%{public}d — %{public}@. Trying IPv4...", port, err);

        asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        host = @"127.0.0.1";
        err = nil;
        if (![asyncSocket connectToHost:host onPort:port error:&err]) {
            DLog("BLUEBUBBLESHELPER[Tahoe]: FAILED to connect to either IPv6 or IPv4 on port %{public}d: %{public}@", port, err);
            return;
        }
    }

    DLog("BLUEBUBBLESHELPER[Tahoe]: Successfully initiated connection to %{public}@:%{public}d", host, port);
    [asyncSocket readDataWithTimeout:(-1) tag:(1)];
}



- (void)disconnect {
    [asyncSocket disconnect];
}

- (void)sendMessage:(NSDictionary*)data {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
    NSString *message = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    // add a newline to the message so back-to-back messages are split and sent correctly
    NSString *jsonMessage = [NSString stringWithFormat:(@"%@\r\n"), message];
    NSData* finalData = [jsonMessage dataUsingEncoding:NSUTF8StringEncoding];
    DLog("BLUEBUBBLESHELPER: Sending data: %{public}@", data);
    [asyncSocket writeData:(finalData) withTimeout:(-1) tag:(1)];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
    DLog("BLUEBUBBLESHELPER: socket:%{public}p didConnectToHost:%{public}@ port:%{public}hu", sock, host, port);
    NSDictionary *message = @{
        @"event": @"ping",
        @"message": @"Helper Connected!",
        @"process": [[NSBundle mainBundle] bundleIdentifier],
    };
    [self sendMessage:message];
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock {
    DLog("BLUEBUBBLESHELPER: socketDidSecure:%{public}p", sock);
}

// called when a message is sent to the server
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    DLog("BLUEBUBBLESHELPER: socket:%p didWriteDataWithTag:%ld", sock, tag);
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSString* str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    DLog("BLUEBUBBLESHELPER: event: %{public}@ socket:%{public}p didReadData:withTag:%{public}ld", str, sock, tag);
    // initiate a new read request for the next data item
    [asyncSocket readDataWithTimeout:(-1) tag:(1)];
    // send the data to the handler
    messageReceivedBlock(self, str);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    DLog("BLUEBUBBLESHELPER: Disconnected from server, attempting to reconnect in 5 seconds... (%{public}@)", err);
    double delayInSeconds = 5.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        DLog("BLUEBUBBLESHELPER: Attempting to reconnect");
        [self connect];
    });
}

@end
