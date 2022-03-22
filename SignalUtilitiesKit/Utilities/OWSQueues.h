//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

#define AssertOnDispatchQueue(queue)                                                                                   \
    {                                                                                                                  \
        dispatch_assert_queue(queue);                                                                                  \
    }

#else

#define AssertOnDispatchQueue(queue)

#endif

NS_ASSUME_NONNULL_END
