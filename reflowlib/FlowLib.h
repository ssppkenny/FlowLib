//
//  djvulibre.h
//  djvulibre
//
//  Created by Sergey Mikhno on 25.08.18.
//  Copyright © 2018 Sergey Mikhno. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#include <opencv2/opencv.hpp>
#include <baseapi.h>

@interface FlowLib : NSObject

+(NSString*)djvuVersion;
+(UIImage*)getPage:(NSString*)filePath for:(int)pageNumber  withContext:(NSManagedObjectContext*)context  width:(int)pageWidth  newScale:(CGFloat)scale flow:(bool)flow;
+(UIImage*)getNewPage:(NSString*)filePath for:(int)pageNumber  withContext:(NSManagedObjectContext*)context  width:(int)pageWidth  newScale:(CGFloat)scale flow:(bool)flow;
+(NSString*)getRecognizedPage:(NSString*)filePath for:(int)pageNumber withTessdata:(NSString*)tessdataPath withContext:(NSManagedObjectContext*)context
    withLang:(NSString*) lang;
+(int)getNumberOfPages:(NSString*)filePath;
@end

@interface ManagedMat : NSManagedObject

//@property (nonatomic) NSData* data;
@property (nonatomic) int pageNo;
@property (nonatomic) NSString* filename;

@end
