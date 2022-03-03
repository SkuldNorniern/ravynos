/* Copyright (c) 2008 Johannes Fortmann
   Copyright (C) 2022 Zoe Knox <zoe@pixin.net>. All rights reserved.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */


#import "WLDisplay.h"
#import "WLWindow.h"
#import <AppKit/NSScreen.h>
#import <AppKit/NSApplication.h>
#import <Foundation/NSSelectInputSource.h>
#import <Foundation/NSSocket_bsd.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/KTFont_FT.h>
#import <AppKit/O2Font_FT.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSWindow.h>
#import <stdio.h>
#import <stdlib.h>
#import <fcntl.h>
#import <errno.h>
#import <unistd.h>
#import <poll.h>
#import <sys/types.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fontconfig.h>
#import <dev/evdev/input-event-codes.h>
#import <X11/keysym.h>

@implementation NSDisplay(WL)

+allocWithZone:(NSZone *)zone {
   return NSAllocateObject([WLDisplay class],0,NULL);
}

@end

@implementation WLDisplay

static int errorHandler(struct wl_display *display,void *errorEvent) {
   return [(WLDisplay*)[WLDisplay currentDisplay] handleError:errorEvent];
}

static void handlePointerEnter(void *data, struct wl_pointer *ptr,
    uint32_t serial, struct wl_surface *surface, wl_fixed_t sx, wl_fixed_t sy) {
    WLDisplay *display = (WLDisplay *)data;
    [display enterSurface:surface];
}

static void handlePointerLeave(void *data, struct wl_pointer *ptr,
    uint32_t serial, struct wl_surface *surface) {
    WLDisplay *display = (WLDisplay *)data;
    [display leaveSurface:surface];
}

static void handlePointerMotion(void *data, struct wl_pointer *ptr,
    uint32_t time, wl_fixed_t sx, wl_fixed_t sy) {
    WLDisplay *display = (WLDisplay *)data;
    [display pointerMotion:time at:NSMakePoint(wl_fixed_to_double(sx), wl_fixed_to_double(sy))];
}

- (void) pointerMotion:(uint32_t)time at:(NSPoint)point
{
    if(_pointerActiveSurface == NULL) {
        NSLog(@"ERROR - motion event without active surface");
        return;
    }
    WLWindow *window = [self windowForID:(unsigned long)_pointerActiveSurface];
    id delegate = [window delegate];

    NSRect bounds = CGOutsetRectForNativeWindowBorder([window frame], [window styleMask]);
    pointerPosition = NSMakePoint(point.x, bounds.size.height - point.y);
    NSPoint pos = [window transformPoint:pointerPosition];
    NSEventType type = NSMouseMoved;
         
    if([self pointerButtonState:WLPointerPrimaryButton] == YES)
        type = NSLeftMouseDragged;
    else if([self pointerButtonState:WLPointerSecondaryButton] == YES)
        type = NSRightMouseDragged;
         
    if(type == NSMouseMoved && ![delegate acceptsMouseMovedEvents])
       return; 

    NSEvent *event = [NSEvent mouseEventWithType:type
                                  location:pos
                             modifierFlags:0 // FIXME: these are keyboard modifier key states
                                    window:delegate
                                clickCount:1 deltaX:0.0 deltaY:0.0];
    [self postEvent:event atStart:NO];
    [self discardEventsMatchingMask:NSLeftMouseDraggedMask beforeEvent:event];
}

static void handlePointerButton(void *data, struct wl_pointer *ptr,
    uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    WLDisplay *display = (WLDisplay *)data;
    [display pointerButton:button time:time state:state];
}

- (void) pointerButton:(uint32_t)button time:(uint32_t)time state:(uint32_t)state
{
    NSEventType type;
    switch(button) {
        case BTN_LEFT: type = (state & WL_POINTER_BUTTON_STATE_RELEASED) ?
                NSLeftMouseUp : NSLeftMouseDown; break;
        case BTN_RIGHT: type = (state & WL_POINTER_BUTTON_STATE_RELEASED) ?
                NSRightMouseUp : NSRightMouseDown; break;
        default: NSLog(@"ignored button %d event", button); return;
    }
    
    NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    if(now - _lastClickTimeStamp < [self doubleClickInterval])
        clickCount++;
    else
        clickCount = 1;
    _lastClickTimeStamp = now;

    // see if we are clicking a surface (window) or on the background
    NSPoint pos = pointerPosition;
    id delegate = nil;
    if(_pointerActiveSurface) {
        WLWindow *window = [self windowForID:(unsigned long)_pointerActiveSurface];
        pos = [window transformPoint:pointerPosition];
        delegate = [window delegate];
    }

    switch(type) {
        case NSLeftMouseUp:
            pointerButtonState &= ~WLPointerPrimaryButton;
            break;
        case NSLeftMouseDown:
            pointerButtonState |= WLPointerPrimaryButton;
            break;
        case NSRightMouseUp:
            pointerButtonState &= ~WLPointerSecondaryButton;
            break;
        case NSRightMouseDown:
            pointerButtonState |= WLPointerSecondaryButton;
            break;
    }

    NSEvent *event = [NSEvent mouseEventWithType:type
                                  location:pos
                             modifierFlags:0 // FIXME: these are keyboard modifier key states
                                    window:delegate
                                clickCount:clickCount deltaX:0.0 deltaY:0.0];
    [self postEvent:event atStart:NO];
}

static void handlePointerAxis(void *data, struct wl_pointer *ptr, uint32_t time,
    uint32_t axis, wl_fixed_t value) {
}

static void handlePointerAxisSource(void *data, struct wl_pointer *ptr, uint32_t source) {
}

static void handlePointerAxisStop(void *data, struct wl_pointer *ptr, uint32_t time, uint32_t axis) {
}

static void handlePointerAxisDiscrete(void *data, struct wl_pointer *ptr, uint32_t axis, int32_t discrete) {
}

static void handlePointerFrame(void *data, struct wl_pointer *ptr) {
}

static const struct wl_pointer_listener wl_pointer_listener = {
    .enter = handlePointerEnter,
    .leave = handlePointerLeave,
    .motion = handlePointerMotion,
    .button = handlePointerButton,
    .axis = handlePointerAxis,
    .frame = handlePointerFrame,
    .axis_source = handlePointerAxisSource,
    .axis_stop = handlePointerAxisStop,
    .axis_discrete = handlePointerAxisDiscrete,
};

static void handle_seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps) {
    WLDisplay *display = (WLDisplay *)data;
    [display seatHasPointer:(caps & WL_SEAT_CAPABILITY_POINTER) ? YES: NO];
}

static void handle_seat_name(void *data, struct wl_seat *seat, const char *name) {
}

static const struct wl_seat_listener wl_seat_listener = {
    .capabilities = handle_seat_capabilities,
    .name = handle_seat_name,
};

-init {
    if(self = [super init]) {

        if(getenv("XDG_RUNTIME_DIR") == NULL) {
            char *buf = 0;
            asprintf(&buf, "/tmp/runtime.%u", getuid());
            setenv("XDG_RUNTIME_DIR", buf, 0);
            if(access(buf, R_OK|W_OK|X_OK) != 0) {
                if(errno == ENOENT)
                    mkdir(buf, 0700);
            }
            free(buf);
        }

        _display = wl_display_connect(NULL);
        if(_display == NULL) {
            [self dealloc];
            return nil;
        }
        _seat = NULL;
        _pointer = NULL;
        
        _fileDescriptor = -1;
        _inputSource = nil; //[[NSSelectInputSource socketInputSourceWithSocket:[NSSocket_bsd socketWithDescriptor:_fileDescriptor]] retain];
        [_inputSource setDelegate:self];
        [_inputSource setSelectEventMask:NSSelectReadEvent];
      
        _windowsByID = [NSMutableDictionary new];

        lastFocusedWindow = nil;
        _pointerActiveSurface = NULL;
        _lastClickTimeStamp = 0.0;
        clickCount = 0;
    }
    return self;
}

-(void)dealloc {
    if(_display)
        wl_display_disconnect(_display);
    
    [_windowsByID release];
    [super dealloc];
}

-(CGWindow *)windowWithFrame:(NSRect)frame styleMask:(unsigned)styleMask backingType:(unsigned)backingType {
	return [[[WLWindow alloc] initWithFrame:frame styleMask:styleMask isPanel:NO backingType:backingType] autorelease];
}

-(CGWindow *)panelWithFrame:(NSRect)frame styleMask:(unsigned)styleMask backingType:(unsigned)backingType {
	return [[[WLWindow alloc] initWithFrame:frame styleMask:styleMask isPanel:YES backingType:backingType] autorelease];
}

-(struct wl_display *)display {
   return _display;
}

-(NSArray *)screens {
   NSRect frame=NSMakeRect(0, 0, 1920, 1080); // FIXME: get this from WindowServer or "new output" events?
                           //DisplayWidth(_display, DefaultScreen(_display)),
                           //DisplayHeight(_display, DefaultScreen(_display)));
   return [NSArray arrayWithObject:[[[NSScreen alloc] initWithFrame:frame visibleFrame:frame] autorelease]];
}

-(NSPasteboard *)pasteboardWithName:(NSString *)name {
   NSUnimplementedMethod();
   return nil;
}

-(NSDraggingManager *)draggingManager {
//   NSUnimplementedMethod();
   return nil;
}



-(NSColor *)colorWithName:(NSString *)colorName {
   if([colorName isEqual:@"controlColor"])
      return [NSColor lightGrayColor];
   if([colorName isEqual:@"disabledControlTextColor"])
      return [NSColor grayColor];
   if([colorName isEqual:@"controlTextColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"menuBackgroundColor"])
      return [NSColor lightGrayColor];
   if([colorName isEqual:@"controlShadowColor"])
      return [NSColor darkGrayColor];
   if([colorName isEqual:@"selectedControlColor"])
      return [NSColor cyanColor];
   if([colorName isEqual:@"controlBackgroundColor"])
      return [NSColor whiteColor];
   if([colorName isEqual:@"controlLightHighlightColor"])
      return [NSColor lightGrayColor];

   if([colorName isEqual:@"textBackgroundColor"])
      return [NSColor whiteColor];
   if([colorName isEqual:@"textColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"menuItemTextColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"selectedMenuItemTextColor"])
      return [NSColor blackColor];
   if([colorName isEqual:@"selectedMenuItemColor"])
      return [NSColor cyanColor];
   if([colorName isEqual:@"selectedControlTextColor"])
      return [NSColor blackColor];
   
   return [NSColor redColor];
   
}

-(void)_addSystemColor:(NSColor *) result forName:(NSString *)colorName {
   NSUnimplementedMethod();
}

-(NSTimeInterval)textCaretBlinkInterval {
   return 0.5;
}

-(void)hideCursor {
   NSUnimplementedMethod();
}

-(void)unhideCursor {
   NSUnimplementedMethod();
}

// Arrow, IBeam, HorizontalResize, VerticalResize
-(id)cursorWithName:(NSString *)name {
   NSUnimplementedMethod();
   return nil;
}

-(void)setCursor:(id)cursor {
   NSUnimplementedMethod();
}

-(void)beep {
   //FIXME beep XBell(_display, 100);
}

-(NSSet *)allFontFamilyNames {
   int i;
   FcPattern *pat=FcPatternCreate();
   FcObjectSet *props=FcObjectSetBuild(FC_FAMILY, NULL);
   
   FcFontSet *set = FcFontList (O2FontSharedFontConfig(), pat, props);
   NSMutableSet* ret=[NSMutableSet set];
   
   for(i = 0; i < set->nfont; i++)
   {
      FcChar8 *family;
      if (FcPatternGetString (set->fonts[i], FC_FAMILY, 0, &family) == FcResultMatch) {
         [ret addObject:[NSString stringWithUTF8String:(char*)family]];
      }
   }
   
   FcPatternDestroy(pat);
   FcObjectSetDestroy(props);
   FcFontSetDestroy(set);
   return ret;
}

-(NSArray *)fontTypefacesForFamilyName:(NSString *)familyName {
   int i;
   FcPattern *pat=FcPatternCreate();
   FcPatternAddString(pat, FC_FAMILY, (unsigned char*)[familyName UTF8String]);
   FcObjectSet *props=FcObjectSetBuild(FC_FAMILY, FC_STYLE, FC_SLANT, FC_WIDTH, FC_WEIGHT, NULL);

   FcFontSet *set = FcFontList (O2FontSharedFontConfig(), pat, props);
   NSMutableArray* ret=[NSMutableArray array];
   
   for(i = 0; i < set->nfont; i++)
   {
      FcChar8 *typeface;
      FcPattern *p=set->fonts[i];
      if (FcPatternGetString (p, FC_STYLE, 0, &typeface) == FcResultMatch) {
         NSString* traitName=[NSString stringWithUTF8String:(char*)typeface];
         FcChar8* pattern=FcNameUnparse(p);
         NSString* name=[NSString stringWithUTF8String:(char*)pattern];
         FcStrFree(pattern);
         
         NSFontTraitMask traits=0;
         int slant, width, weight;
         
         FcPatternGetInteger(p, FC_SLANT, FC_SLANT_ROMAN, &slant);
         FcPatternGetInteger(p, FC_WIDTH, FC_WIDTH_NORMAL, &width);
         FcPatternGetInteger(p, FC_WEIGHT, 0, &weight);

         switch(slant) {
            case FC_SLANT_OBLIQUE:
            case FC_SLANT_ITALIC:
               traits|=NSItalicFontMask;
               break;
         }
         
         if(weight>FC_WEIGHT_SEMIBOLD)
            traits|=NSBoldFontMask;

         if(width<=FC_WIDTH_SEMICONDENSED)
            traits|=NSNarrowFontMask;
         else if(width>=FC_WIDTH_SEMIEXPANDED)
            traits|=NSExpandedFontMask;

        // FIXME: we should set FixedPitch (monospace) and other attrs too (see NSFontManager.h)
         
         name = [NSString stringWithFormat:@"%@-%@",
            [[[[name componentsSeparatedByString:@":"] firstObject] // strip off any 'style=XXX' stuff
            componentsSeparatedByString:@","] firstObject],         // and any multiple names
            traitName]; // and append "-Traits"
         NSFontTypeface *face=[[NSFontTypeface alloc] initWithName:name traitName:traitName traits:traits];
         [ret addObject:face];
         [face release];
      }
   }
   
   FcPatternDestroy(pat);
   FcObjectSetDestroy(props);
   FcFontSetDestroy(set);
   return ret;
}

-(float)scrollerWidth {
   return 15.0;
}

-(float)doubleClickInterval {
   return 1.0;
}


-(int)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo {
   NSUnimplementedMethod();
	return 0;
}

-(int)runModalPrintPanelWithPrintInfoDictionary:(NSMutableDictionary *)attributes {
   NSUnimplementedMethod();
   return 0;
}

-(O2Context *)graphicsPortForPrintOperationWithView:(NSView *)view printInfo:(NSPrintInfo *)printInfo pageRange:(NSRange)pageRange {
   NSUnimplementedMethod();
   return nil;
}

-(int)savePanel:(NSSavePanel *)savePanel runModalForDirectory:(NSString *)directory file:(NSString *)file {
   NSUnimplementedMethod();
   return 0;
}

-(int)openPanel:(NSOpenPanel *)openPanel runModalForDirectory:(NSString *)directory file:(NSString *)file types:(NSArray *)types {
   NSUnimplementedMethod();
   return 0;
}

-(NSPoint)mouseLocation {
#if 0 // FIXME: get this from WindowServer
    int rootX, rootY;

    BOOL result = XQueryPointer(_display, DefaultRootWindow(_display),
        &window, &window, &rootX, &rootY, &winX, &winY, &mask);
    if(result == YES) {
        // invert the Y since Cocoa's origin is lower left
        int height = DisplayHeight(_display, DefaultScreen(_display));
        return NSMakePoint(rootX, height - rootY);
    }
#endif
    NSLog(@"-[WLDisplay mouseLocation] unable to locate mouse pointer");
    return NSMakePoint(0,0);
}

-(void)setWindow:(id)window forID:(unsigned long)i
{
   if(window)
      [_windowsByID setObject:window forKey:[NSNumber numberWithUnsignedLong:(unsigned long)i]];
   else
      [_windowsByID removeObjectForKey:[NSNumber numberWithUnsignedLong:(unsigned long)i]];
}

- (void)setSeat:(struct wl_seat *)seat
{
    _seat = seat;
    wl_seat_add_listener(seat, &wl_seat_listener, (void *)self);
}

- (void)seatHasPointer:(BOOL)hasPointer
{
    if(_pointer)
        wl_pointer_release(_pointer);
    if(hasPointer) {
        _pointer = wl_seat_get_pointer(_seat);
        wl_pointer_add_listener(_pointer, &wl_pointer_listener, (void *)self);
    }
}

- (void)enterSurface:(struct wl_surface *)surface
{
    _pointerActiveSurface = surface;
}

- (void)leaveSurface:(struct wl_surface *)surface
{
    if(_pointerActiveSurface == surface)
        _pointerActiveSurface = NULL;
}

- (struct wl_surface *)pointerActiveSurface
{
    return _pointerActiveSurface;
}

- (NSTimeInterval)lastClickTimeStamp
{
    return _lastClickTimeStamp;
}

- (void)setLastClickTimeStamp:(NSTimeInterval)now
{
    _lastClickTimeStamp = now;
}

- (BOOL)pointerButtonState:(WLPointerButtonMask)mask
{
    if((pointerButtonState & mask) == mask)
        return YES;
    return NO;
}

-(id)windowForID:(unsigned long)i
{
   return [_windowsByID objectForKey:[NSNumber numberWithUnsignedLong:i]];
}

-(NSEvent *)nextEventMatchingMask:(unsigned)mask untilDate:(NSDate *)untilDate inMode:(NSString *)mode dequeue:(BOOL)dequeue {
   NSEvent *result;

    while(wl_display_prepare_read(_display) != 0)
        wl_display_dispatch_pending(_display);
    wl_display_flush(_display);

    struct pollfd pfd;
    pfd.fd = wl_display_get_fd(_display);
    pfd.events = POLLIN;
    pfd.revents = POLLIN;

    if(poll(&pfd, 1, 0) > 0) {
        wl_display_read_events(_display);
    } else {
        wl_display_cancel_read(_display);
    }

    wl_display_dispatch_pending(_display);

    // wake up the main event loop so we don't block
    // FIXME: there must be a more optimal way to do this
    NSEvent *event = [NSEvent mouseEventWithType:NSMouseMoved
                                 location:NSMakePoint(0,0)
                            modifierFlags:0
                                   window:nil
                               clickCount:1 deltaX:0.0 deltaY:0.0];
    [self postEvent:event atStart:NO];

    [[NSRunLoop currentRunLoop] addInputSource:_inputSource forMode:mode];
    result=[super nextEventMatchingMask:mask untilDate:untilDate inMode:mode dequeue:dequeue];
    [[NSRunLoop currentRunLoop] removeInputSource:_inputSource forMode:mode];
   
    return result;
}

-(unsigned int)modifierFlagsForState:(unsigned int)state {
   unsigned int ret=0;
#if 0 // FIXME: should be in compositor?
   if(state & ShiftMask)
      ret|=NSShiftKeyMask;
   if(state & ControlMask)
      ret|=NSControlKeyMask;
   if(state & Mod2Mask)
      ret|=NSCommandKeyMask;
   // TODO: alt doesn't work; might want to track key presses/releases instead
#endif
   return ret;
}

NSArray *CGSOrderedWindowNumbers() {
    NSMutableArray *result = [NSMutableArray array];
    
    for (NSWindow* win in [NSApp windows]) [result addObject:[NSNumber numberWithInteger:[win windowNumber]]];
    
    NSUnimplementedFunction(); //(Window numbers not even remotely ordered)
    
    return result;
}

#if 0 // FIXME: this belongs in compositor?
-(void)postXEvent:(XEvent *)ev {
   id event=nil;
   NSEventType type;
   id window=[self windowForID:ev->xany.window];
   if(window == nil) { // guard against unknown IDs
      //NSLog(@"postXEvent: unknown window ID %d",ev->xany.window);
      return;
   }
   id delegate=[window delegate];
   
   switch(ev->type) {
    case KeyPress:
    case KeyRelease:;
     unsigned int modifierFlags=[self modifierFlagsForState:ev->xkey.state];
     unichar keys[32]={0};
     size_t buflen = 0;
     char buf[4];
     
     KeySym ks;
     XLookupString((XKeyEvent*)ev, buf, 4, &ks, NULL);

     // translate special characters
     switch(ks) {
        case XK_Home:
        case XK_KP_Home: keys[buflen++] = NSHomeFunctionKey; break;
        case XK_Left:
        case XK_KP_Left: keys[buflen++] = NSLeftArrowFunctionKey; break;
        case XK_Up:
        case XK_KP_Up: keys[buflen++] = NSUpArrowFunctionKey; break;
        case XK_Right:
        case XK_KP_Right: keys[buflen++] = NSRightArrowFunctionKey; break;
        case XK_Down:
        case XK_KP_Down: keys[buflen++] = NSDownArrowFunctionKey; break;
        case XK_Page_Up:
        case XK_KP_Page_Up: keys[buflen++] = NSPageUpFunctionKey; break;
        case XK_Page_Down:
        case XK_KP_Page_Down: keys[buflen++] = NSPageDownFunctionKey; break;
        case XK_End:
        case XK_KP_End: keys[buflen++] = NSEndFunctionKey; break;
        case XK_Begin:
        case XK_KP_Begin: keys[buflen++] = NSHomeFunctionKey; break;
        case XK_Delete:
        case XK_KP_Delete: keys[buflen++] = NSDeleteFunctionKey; break;
        case XK_Insert:
        case XK_KP_Insert: keys[buflen++] = NSInsertFunctionKey; break;
        case XK_F1: keys[buflen++] = NSF1FunctionKey; break;
        case XK_F2: keys[buflen++] = NSF2FunctionKey; break;
        case XK_F3: keys[buflen++] = NSF3FunctionKey; break;
        case XK_F4: keys[buflen++] = NSF4FunctionKey; break;
        case XK_F5: keys[buflen++] = NSF5FunctionKey; break;
        case XK_F6: keys[buflen++] = NSF6FunctionKey; break;
        case XK_F7: keys[buflen++] = NSF7FunctionKey; break;
        case XK_F8: keys[buflen++] = NSF8FunctionKey; break;
        case XK_F9: keys[buflen++] = NSF9FunctionKey; break;
        case XK_F10: keys[buflen++] = NSF10FunctionKey; break;
        case XK_F11: keys[buflen++] = NSF11FunctionKey; break;
        case XK_F12: keys[buflen++] = NSF12FunctionKey; break;
        case XK_F13: keys[buflen++] = NSF13FunctionKey; break;
        case XK_F14: keys[buflen++] = NSF14FunctionKey; break;
        case XK_F15: keys[buflen++] = NSF15FunctionKey; break;
        case XK_F16: keys[buflen++] = NSF16FunctionKey; break;
        case XK_F17: keys[buflen++] = NSF17FunctionKey; break;
        case XK_F18: keys[buflen++] = NSF18FunctionKey; break;
        case XK_F19: keys[buflen++] = NSF19FunctionKey; break;
        case XK_F20: keys[buflen++] = NSF20FunctionKey; break;
        case XK_F21: keys[buflen++] = NSF21FunctionKey; break;
        case XK_F22: keys[buflen++] = NSF22FunctionKey; break;
        case XK_F23: keys[buflen++] = NSF23FunctionKey; break;
        case XK_F24: keys[buflen++] = NSF24FunctionKey; break;
        case XK_F25: keys[buflen++] = NSF25FunctionKey; break;
        case XK_F26: keys[buflen++] = NSF26FunctionKey; break;
        case XK_F27: keys[buflen++] = NSF27FunctionKey; break;
        case XK_F28: keys[buflen++] = NSF28FunctionKey; break;
        case XK_F29: keys[buflen++] = NSF29FunctionKey; break;
        case XK_F30: keys[buflen++] = NSF30FunctionKey; break;
        case XK_F31: keys[buflen++] = NSF31FunctionKey; break;
        case XK_F32: keys[buflen++] = NSF32FunctionKey; break;
        case XK_F33: keys[buflen++] = NSF33FunctionKey; break;
        case XK_F34: keys[buflen++] = NSF34FunctionKey; break;
        case XK_F35: keys[buflen++] = NSF35FunctionKey; break;
        default: keys[buflen++] = buf[0];
     }

     id str=[[NSString alloc] initWithCharacters:keys length:buflen];
     NSPoint pos=[window transformPoint:NSMakePoint(ev->xkey.x, ev->xkey.y)];

     id strIg=[str lowercaseString];
     if(ev->xkey.state) {
      ev->xkey.state=0;
      XLookupString((XKeyEvent*)ev, buf, 4, NULL, NULL);
      strIg=[[NSString alloc] initWithCharacters:buf length:1];
     }
      
     id event=[NSEvent keyEventWithType:ev->type == KeyPress ? NSKeyDown : NSKeyUp location:pos
                              modifierFlags:modifierFlags
                                  timestamp:0.0 
                               windowNumber:(NSInteger)[delegate windowNumber]
                                    context:nil
                                 characters:str 
                charactersIgnoringModifiers:strIg
                                  isARepeat:NO
                                    keyCode:ev->xkey.keycode]; // FIXME: translate these to Apple keycodes?
         
     [self postEvent:event atStart:NO];
         
     [str release];
     break;


    case FocusIn:
     if([delegate attachedSheet]) {
      [[delegate attachedSheet] makeKeyAndOrderFront:delegate];
      break;
     }
     if(lastFocusedWindow) {
      [lastFocusedWindow platformWindowDeactivated:window checkForAppDeactivation:NO];
      lastFocusedWindow=nil;  
     }
     [delegate platformWindowActivated:window displayIfNeeded:YES];
     lastFocusedWindow=delegate;
     break;
     
    case FocusOut:
     [delegate platformWindowDeactivated:window checkForAppDeactivation:NO];
     lastFocusedWindow=nil;
     break;
         
    case KeymapNotify:
     NSLog(@"KeymapNotify");
     break;

    case Expose:;
     O2Rect rect=NSMakeRect(ev->xexpose.x, ev->xexpose.y, ev->xexpose.width, ev->xexpose.height);
     
     rect.origin.y=[window frame].size.height-rect.origin.y-rect.size.height;
     // rect=NSInsetRect(rect, -10, -10);
     // [_backingContext addToDirtyRect:rect];
     if(ev->xexpose.count==0)
      [window flushBuffer];
     break;


    case DestroyNotify:;
     // we should never get this message before the WM_DELETE_WINDOW ClientNotify
     // so normally, window should be nil here.
     [window invalidate];
     break;

    case ConfigureNotify:
     [window frameChanged];
     [delegate platformWindow:window frameChanged:[window transformFrame:[window frame]] didSize:YES];
     break;

    case ConfigureRequest:
     NSLog(@"ConfigureRequest");
     break;

    case GravityNotify:
     NSLog(@"GravityNotify");
     break;

    case ResizeRequest:
     NSLog(@"ResizeRequest");
     break;

    case CirculateNotify:
     NSLog(@"CirculateNotify");
     break;

    case CirculateRequest:
     NSLog(@"CirculateRequest");
     break;

    case PropertyNotify:
     NSLog(@"PropertyNotify");
     break;

    case SelectionClear:
     NSLog(@"SelectionClear");
     break;

    case SelectionRequest:
     NSLog(@"SelectionRequest");
     break;

    case SelectionNotify:
     NSLog(@"SelectionNotify");
     break;

    case ColormapNotify:
     NSLog(@"ColormapNotify");
     break;

    case ClientMessage:
     if(ev->xclient.format=32 && ev->xclient.data.l[0]==XInternAtom(_display, "WM_DELETE_WINDOW", False))
      [delegate platformWindowWillClose:window];
     break;

    case MappingNotify:
     NSLog(@"MappingNotify");
     break;

    case GenericEvent:
     NSLog(@"GenericEvent");
     break;

    default:
     NSLog(@"Unknown WL event type %i", ev->type);
     break;
   }

}
#endif

-(void)selectInputSource:(NSSelectInputSource *)inputSource selectEvent:(NSUInteger)selectEvent {
    //[self postXEvent:&e];
}

-(int)handleError:(void*)errorEvent {
   NSLog(@"************** ERROR");
   return 0;
}
@end

#import <AppKit/NSGraphicsStyle.h>

@implementation NSGraphicsStyle (Overrides) 
-(void)drawMenuBranchArrowInRect:(NSRect)rect selected:(BOOL)selected {
    NSImage* arrow=[NSImage imageNamed:@"NSMenuArrow"];
    // ??? magic numbers
    rect.origin.y+=5;
    rect.origin.x-=2;
    [arrow drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}

@end
