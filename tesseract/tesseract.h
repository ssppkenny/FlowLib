//
//  tesseract.h
//  tesseract
//
//  Created by Sergey Mikhno on 29.12.19.
//  Copyright © 2019 Sergey Mikhno. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <tesseract/version.h>

@interface tesseract : NSObject

+(NSString*)recognize();

@end
