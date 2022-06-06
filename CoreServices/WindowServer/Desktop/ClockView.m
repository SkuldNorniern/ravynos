/*
 * Copyright (C) 2022 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <AppKit/AppKit.h>
#import "desktop.h"

const NSString *PrefsDateFormatStringKey = @"DateFormatString";
const NSString *defaultFormatEN = @"%a %b %d  %I:%M %p";
pthread_t updater;

static void clockLoop(void *arg) {
    ClockView *cv = (__bridge ClockView *)arg;
    [cv update:[cv window]];
}

@implementation ClockView
- init {
    NSRect frame = [[NSScreen mainScreen] visibleFrame];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    dateFormat = [prefs stringForKey:PrefsDateFormatStringKey];
    if(dateFormat == nil || [dateFormat length] == 0) {
        NSString *locale = [[NSLocale currentLocale] localeIdentifier];
        if([locale hasPrefix:@"en"])
            dateFormat = defaultFormatEN;
        else
            dateFormat = [prefs objectForKey:NSTimeDateFormatString];
    }
    dateFormatter = [[NSDateFormatter alloc] initWithDateFormat:dateFormat 
        allowNaturalLanguage:YES locale:[NSLocale currentLocale]];

    self = [super initWithFrame:NSMakeRect(frame.size.width - 300, menuBarVPad, 300, menuBarHPad)];
    [self setDrawsBackground:NO];
    [self setEditable:NO];
    NSFont *font = [NSFont systemFontOfSize:15];
    attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];

    NSTextStorage *textStorage = [self textStorage];
    [textStorage beginEditing];
    [textStorage setAttributedString:[[NSAttributedString alloc]
            initWithString:[dateFormatter stringForObjectValue:[NSDate date]]
            attributes:attributes]];
    [textStorage endEditing];

    NSRect f = [self frame];
    f.size = [[self textStorage] size];
    f.origin.x = frame.size.width - f.size.width - menuBarHPad;
    [self setFrame:f];
    pthread_create(&updater, NULL, clockLoop, (__bridge void *)self);

    return self;
}

- (void)update:(NSWindow*)window {
    NSTextStorage *textStorage = [self textStorage];
    while(1) {
        @autoreleasepool {
            [textStorage beginEditing];
            [textStorage replaceCharactersInRange:NSMakeRange(0,[[textStorage string] length])
                withString:[dateFormatter stringForObjectValue:[NSDate date]]];
            [textStorage endEditing];
        }
        usleep(500000);
    }
}

@end

