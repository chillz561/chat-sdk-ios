//
//  BFirebaseMessagingHandler.m
//  Pods
//
//  Created by Benjamin Smiley-andrews on 12/11/2016.
//
//

#import "BFirebaseCoreHandler.h"

#import <ChatSDK/ChatCore.h>
#import <ChatSDK/ChatFirebaseAdapter.h>


@implementation BFirebaseCoreHandler

-(RXPromise *) pushUser {
    [self save];
    return [self.currentUser push];
}

-(id<PUser>) currentUserModel {
    NSString * currentUserID = [BNetworkManager sharedManager].a.auth.currentUserEntityID;
    
    return [[BStorageManager sharedManager].a fetchEntityWithID:currentUserID
                                                             withType:bUserEntity];
}

-(void) setUserOnline {
    id<PUser> user = self.currentUserModel;
    if(!user || !user.entityID) {
        return;
    }
    [[CCUserWrapper userWithModel:user] goOnline];
}

-(void) goOnline {
    [super goOnline];
    [FIRDatabaseReference goOnline];
    if (self.currentUserModel) {
        [self setUserOnline];
    }
}

-(void) goOffline {
    [FIRDatabaseReference goOffline];
}

-(void)observeUser: (NSString *)entityID {
    id<PUser> contactModel = [[BStorageManager sharedManager].a fetchOrCreateEntityWithID:entityID withType:bUserEntity];
    [[CCUserWrapper userWithModel:contactModel] metaOn];
    [[CCUserWrapper userWithModel:contactModel] onlineOn];
}

-(RXPromise *) createThreadWithUsers: (NSArray *) users name: (NSString *) name threadCreated: (void(^)(NSError * error, id<PThread> thread)) threadCreated {
    id<PUser> currentUser = self.currentUserModel;
    
    NSMutableArray * usersToAdd = [NSMutableArray arrayWithArray:users];
    if (![usersToAdd containsObject:currentUser]) {
        [usersToAdd addObject:currentUser];
    }
    
    //id<PThread> thready = [self threadAlreadyExists:users];
    
    // If there are only two users check to see if a thread already exists
    if (usersToAdd.count == 2) {
        // Check to see if we already have a chat with this user
        id<PThread> jointThread = Nil;
        id<PUser> otherUser = Nil;
        for (id<PUser> user in usersToAdd) {
            if (![user isEqual:currentUser]) {
                otherUser = user;
                break;
            }
        }
        
        // Check to see if a thread already exists with these
        // two users
        for (id<PThread> thread in [[BNetworkManager sharedManager].a.core threadsWithType:bThreadType1to1]) {
            if (thread.users.count == 2 && [thread.users containsObject:currentUser] && [thread.users containsObject:otherUser]) {
                jointThread = thread;
                break;
            }
        }
        
        // Complete with the thread
        if(jointThread) {
            [jointThread setDeleted: @NO];
            if (threadCreated != Nil) {
                threadCreated(Nil, jointThread);
                
                // We've found the thread so return
                RXPromise * promise = [RXPromise new];
                [promise resolveWithResult:Nil];
                return promise;
            }
        }
    }
    
    // Before we create the thread start an undo grouping
    // that means that if it fails we can undo changed to the database
    [[BStorageManager sharedManager].a beginUndoGroup];
    
    id<PThread> threadModel = [[BStorageManager sharedManager].a createEntity:bThreadEntity];
    threadModel.creationDate = [NSDate date];
    threadModel.creator = currentUser;
    threadModel.type = usersToAdd.count == 2 ? @(bThreadType1to1) : @(bThreadTypePrivateGroup);
    threadModel.name = name;
    
    CCThreadWrapper * thread = [CCThreadWrapper threadWithModel:threadModel];
    
    return [thread push].thenOnMain(^id(id<PThread> thread) {
        
        [[BStorageManager sharedManager].a endUndoGroup];
        // Add the users to the thread
        if (threadCreated != Nil) {
            threadCreated(Nil, thread);
        }
        return [self addUsers:usersToAdd toThread:threadModel];
        
    },^id(NSError * error) {
        [[BStorageManager sharedManager].a endUndoGroup];
        [[BStorageManager sharedManager].a undo];
        
        if (threadCreated != Nil) {
            threadCreated(error, Nil);
        }
        return error;
    });
}

-(RXPromise *) createThreadWithUsers: (NSArray *) users threadCreated: (void(^)(NSError * error, id<PThread> thread)) threadCreated {
    return [self createThreadWithUsers:users name:nil threadCreated:threadCreated];
}


-(RXPromise *) addUsers: (NSArray<PUser> *) users toThread: (id<PThread>) threadModel {
    
    CCThreadWrapper * thread = [CCThreadWrapper threadWithModel:threadModel];
    
    NSMutableArray * promises = [NSMutableArray new];
    
    // Push each user to make sure they have an account
    for (id<PUser> userModel in users) {
        [promises addObject:[thread addUser:[CCUserWrapper userWithModel:userModel]]];
    }
    
    return [RXPromise all: promises];
}

-(RXPromise *) removeUsers: (NSArray<PUser> *) users fromThread: (id<PThread>) threadModel {
    
    CCThreadWrapper * thread = [CCThreadWrapper threadWithModel:threadModel];
    
    NSMutableArray * promises = [NSMutableArray new];
    
    // Push each user to make sure they have an account
    for (id<PUser> userModel in users) {
        [promises addObject:[thread removeUser:[CCUserWrapper userWithModel:userModel]]];
    }
    
    return [RXPromise all: promises];
    
}

-(RXPromise *) loadMoreMessagesForThread: (id<PThread>) threadModel {
    CCThreadWrapper * thread = [CCThreadWrapper threadWithModel:threadModel];
    return [thread loadMoreMessages: 10];
}

-(RXPromise *) deleteThread: (id<PThread>) thread {
    return [[CCThreadWrapper threadWithModel:thread] deleteThread];
}

// TODO: Implement this
-(RXPromise *) leaveThread: (id<PThread>) thread {
    
}

-(RXPromise *) joinThread: (id<PThread>) thread {
    
}

-(RXPromise *) sendMessage: (id<PMessage>) messageModel {
    
    // Create the new CCMessage wrapper
    return [[CCMessageWrapper messageWithModel:messageModel] send].thenOnMain(^id(id success) {
        [[BNetworkManager sharedManager].a.push pushForMessage:messageModel];
        return success;
    }, Nil);
    
}

// TODO: Implement these
-(RXPromise *) setChatState: (bChatState) state forThread: (id<PThread>) thread {
    
}

-(RXPromise *) acceptSubscriptionRequestForUser: (id<PUser>) user {
    
}

-(RXPromise *) rejectSubscriptionRequestForUser: (id<PUser>) user {
    
}

#pragma Private methods

-(CCUserWrapper *) currentUser {
    return [CCUserWrapper userWithModel:self.currentUserModel];
}

#pragma Static methods

+(NSDate *) timestampToDate:(NSNumber *)timestamp {
    return [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue / 1000];
}

+(NSNumber *) dateToTimestamp:(NSDate *)date {
    return @((double)date.timeIntervalSince1970 * 1000);
}


@end
