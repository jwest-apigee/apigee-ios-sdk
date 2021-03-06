/*
 * Copyright 2014 Apigee Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ApigeeCollection.h"
#import "ApigeeClientResponse.h"
#import "ApigeeDataClient.h"
#import "ApigeeEntity.h"
#import "ApigeeQuery.h"

@interface ApigeeCollection ()
{
	NSString* _type;
	NSMutableDictionary* _qs;
	NSMutableArray* _list;
	int _iterator;
	NSMutableArray* _previous;
	NSString* _next;
	NSString* _cursor;
    ApigeeQuery* _query;
}

@end


@implementation ApigeeCollection

@synthesize dataClient=_dataClient;
@synthesize type=_type;
@synthesize qs=_qs;
@synthesize list=_list;
@synthesize previous=_previous;
@synthesize next=_next;
@synthesize cursor=_cursor;
@synthesize query=_query;

- (id)init:(ApigeeDataClient*)theDataClient type:(NSString*)type qs:(NSDictionary*)qs
{
    self = [super init];
    if( self )
    {
	    _dataClient = theDataClient;
	    _type = type;
	    
	    if( qs == nil )
	    {
	    	_qs = [[NSMutableDictionary alloc] init];
	    }
	    else
	    {
	    	_qs = [[NSMutableDictionary alloc] initWithDictionary:qs];
	    }
        
	    _list = [[NSMutableArray alloc] init];
	    _iterator = -1;
        
	    _previous = [[NSMutableArray alloc] init];
	    _next = nil;
	    _cursor = nil;
        
	    [self fetch];
    }
    
    return self;
}

- (id)init:(ApigeeDataClient*)theDataClient type:(NSString*)type query:(ApigeeQuery *)theQuery
{
    self = [super init];
    if( self )
    {
	    _dataClient = theDataClient;
	    _type = type;
	    
        _query = theQuery;
        
	    _list = [[NSMutableArray alloc] init];
	    _iterator = -1;
        
	    _previous = [[NSMutableArray alloc] init];
	    _next = nil;
	    _cursor = nil;
        
	    [self fetch];
    }
    
    return self;
}

- (id)init:(ApigeeDataClient*)theDataClient
      type:(NSString*)type
        qs:(NSDictionary*)qs
completionHandler:(ApigeeDataClientCompletionHandler)completionHandler
{
    self = [super init];
    if (self) {
        _dataClient = theDataClient;
	    _type = type;
	    
	    if( qs == nil )
	    {
	    	_qs = [[NSMutableDictionary alloc] init];
	    }
	    else
	    {
	    	_qs = [[NSMutableDictionary alloc] initWithDictionary:qs];
	    }
        
	    _list = [[NSMutableArray alloc] init];
	    _iterator = -1;
        
	    _previous = [[NSMutableArray alloc] init];
	    _next = nil;
	    _cursor = nil;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            ApigeeClientResponse* response = [self fetch];
            if (completionHandler) {
                completionHandler(response);
            }
        });
    }
    
    return self;
}

- (id)init:(ApigeeDataClient*)theDataClient
      type:(NSString*)type
     query:(ApigeeQuery*)theQuery
completionHandler:(ApigeeDataClientCompletionHandler)completionHandler
{
    self = [super init];
    if (self) {
	    _dataClient = theDataClient;
	    _type = type;
	    
        _query = theQuery;
        
	    _list = [[NSMutableArray alloc] init];
	    _iterator = -1;
        
	    _previous = [[NSMutableArray alloc] init];
	    _next = nil;
	    _cursor = nil;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            ApigeeClientResponse* response = [self fetch];
            if (completionHandler) {
                completionHandler(response);
            }
        });
    }
    
    return self;
}

- (ApigeeClientResponse*)fetch
{
    ApigeeQuery* theQuery = nil;

    if (self.query) {
        if( self.cursor != nil ) {
            // Lets make a copy and add the "cursor" requirement.  This way it won't always be attached to our self.query object.
            theQuery = [self.query copy];
            [theQuery addRequiredOperation:@"cursor" op:kApigeeQueryOperationEquals valueStr:self.cursor];
        } else {
            theQuery = self.query;
        }
    } else {
        if (self.cursor != nil) {
            if( self.qs == nil ) {
                self.qs = [[NSMutableDictionary alloc] init];
            }
            [self.qs setValue:self.cursor forKey:@"cursor"];
        } else if ( [self.qs valueForKey:@"cursor"]  != nil ) {
            [self.qs removeObjectForKey:@"cursor"];
        }
        if( [self.qs count] > 0 ) {
            theQuery = [ApigeeQuery queryFromDictionary:self.qs];
        }
    }
    
    ApigeeClientResponse* response = [self.dataClient getEntities:self.type
                                                            query:theQuery];
    
    if ([response error] != nil) {
        [self.dataClient writeLog:@"Error getting collection."];
    } else {
        NSString* theCursor = [response cursor];
        NSUInteger count = [response entityCount];
        self.next = [response next];
        self.cursor = theCursor;
        
        [self saveCursor:theCursor];
        [self resetEntityPointer];
        [self.list removeAllObjects];

        if ( count > 0 ) {
            NSArray* retrievedEntities = [response entities];
            
            for( ApigeeEntity* retrievedEntity in retrievedEntities ) {
                if( retrievedEntity.uuid != nil ) {
                    retrievedEntity.type = self.type;
                    [self.list addObject:retrievedEntity];
                }
            }
        }
    }
    
    return response;
}
    
- (ApigeeEntity*)addEntity:(NSDictionary*)entityData
{
    ApigeeEntity* entity = nil;
    ApigeeClientResponse* response = [self.dataClient createEntity:entityData];
    
    if( (response != nil) && (response.transactionState == kApigeeClientResponseSuccess) ) {
        entity = [response firstEntity];
        if ((entity != nil) && ([[entity uuid] length] > 0)) {
            [self.list addObject:entity];
        }
    }
    
    return entity;
}
    
- (ApigeeClientResponse*)destroyEntity:(ApigeeEntity*)entity
{
    ApigeeClientResponse* response = [entity destroy];
    if ([response error] != nil) {
        [self.dataClient writeLog:@"Could not destroy entity."];
    } else {
        response = [self fetch];
    }
	    
    return response;
}
    
- (ApigeeClientResponse*)getEntityByUuid:(NSString*)uuid
{
    ApigeeEntity* entity = [self.dataClient createTypedEntity:self.type];
    entity.type = self.type;
    entity.uuid = uuid;
    return [entity fetch];
}
    
- (ApigeeEntity*)getFirstEntity
{
    return ([self.list count] > 0 ? [self.list objectAtIndex:0] : nil);
}
    
- (ApigeeEntity*)getLastEntity
{
    return ([self.list count] > 0 ? [self.list objectAtIndex:[self.list count]-1] : nil);
}

- (BOOL)hasNextEntity
{
    const int next = _iterator + 1;
    return ((next >= 0) && (next < [self.list count]));
}
    
- (BOOL)hasPrevEntity
{
    const int prev = _iterator - 1;
    return ((prev >= 0) && (prev < [self.list count]));
}
    
- (ApigeeEntity*)getNextEntity
{
    if ([self hasNextEntity]) {
        _iterator++;
		return [self.list objectAtIndex:_iterator];
    }
    return nil;
}
    
- (ApigeeEntity*)getPrevEntity
{
    if ([self hasPrevEntity]) {
        _iterator--;
        return [self.list objectAtIndex:_iterator];
    }
    return nil;
}
    
- (void)resetEntityPointer
{
    _iterator = -1;
}
    
- (void)saveCursor:(NSString*)cursor
{
    self.next = cursor;
}
    
- (void)resetPaging
{
    [self.previous removeAllObjects];
    self.next = nil;
    self.cursor = nil;
}
    
- (BOOL)hasNextPage
{
    return (self.next != nil);
}
    
- (BOOL)hasPrevPage
{
    return ([self.previous count] > 0);
}
    
- (ApigeeClientResponse*)getNextPage
{
    if ( [self hasNextPage] ) {
        [self.previous addObject:self.cursor];
		self.cursor = self.next;
        [self.list removeAllObjects];
        return [self fetch];
    }
    
    return nil;
}
    
- (ApigeeClientResponse*)getPrevPage
{
    if ( [self hasPrevPage] ) {
		self.next = nil;
        self.cursor = [self.previous lastObject];
        [self.previous removeLastObject];
        [self.list removeAllObjects];
        return [self fetch];
    }
        
    return nil;
}
    

@end
