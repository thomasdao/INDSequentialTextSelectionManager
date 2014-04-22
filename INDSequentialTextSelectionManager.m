//
//  INDSequentialTextSelectionManager.m
//  INDSequentialTextSelectionManager
//
//  Created by Indragie Karunaratne on 2014-03-02.
//  Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
//

#import "INDSequentialTextSelectionManager.h"
#import <objc/runtime.h>

static NSUInteger INDCharacterIndexForTextViewEvent(NSEvent *event, NSTextView *textView)
{
	NSView *contentView = event.window.contentView;
	NSPoint point = [contentView convertPoint:event.locationInWindow fromView:nil];
	NSPoint textPoint = [textView convertPoint:point fromView:contentView];
	return [textView characterIndexForInsertionAtPoint:textPoint];
}

static NSRange INDForwardRangeForIndices(NSUInteger idx1, NSUInteger idx2) {
	NSRange range;
	if (idx2 >= idx1) {
		range = NSMakeRange(idx1, idx2 - idx1);
	} else if (idx2 < idx1) {
		range = NSMakeRange(idx2, idx1 - idx2);
	} else {
		range = NSMakeRange(NSNotFound, 0);
	}
	return range;
}

static void INDSwizzle(Class c, SEL orig, SEL new)
{
    Method origMethod = class_getInstanceMethod(c, orig);
    Method newMethod = class_getInstanceMethod(c, new);
    if (class_addMethod(c, orig, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, new, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

static void * INDUniqueIdentifierKey = &INDUniqueIdentifierKey;

@interface NSTextView (INDUniqueIdentifiers)
@property (nonatomic, copy) NSString *ind_uniqueIdentifier;
@end

@implementation NSTextView (INDUniqueIdentifiers)

- (void)setInd_uniqueIdentifier:(NSString *)ind_uniqueIdentifier
{
	objc_setAssociatedObject(self, INDUniqueIdentifierKey, ind_uniqueIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)ind_uniqueIdentifier
{
	return objc_getAssociatedObject(self, INDUniqueIdentifierKey);
}

@end

@interface INDAttributeRange : NSObject
@property (nonatomic, copy, readonly) NSString *attribute;
@property (nonatomic, strong, readonly) id value;
@property (nonatomic, assign, readonly) NSRange range;
- (id)initWithAttribute:(NSString *)attribute value:(id)value range:(NSRange)range;
@end

@implementation INDAttributeRange

- (id)initWithAttribute:(NSString *)attribute value:(id)value range:(NSRange)range
{
	if ((self = [super init])) {
		_attribute = [attribute copy];
		_value = value;
		_range = range;
	}
	return self;
}

@end

static void * INDFixSelectionHighlightKey = &INDFixSelectionHighlightKey;
static void * INDBackgroundColorRangesKey = &INDBackgroundColorRangesKey;

#define IND_DISABLED_SELECTED_TEXT_BG_COLOR [NSColor colorWithDeviceRed:0.83 green:0.83 blue:0.83 alpha:1.0]

@interface NSTextView (INDSelectionHighlight)
@property (nonatomic, assign) BOOL ind_fixSelectionHighlight;
@property (nonatomic, strong) NSArray *ind_backgroundColorRanges;
@end

@implementation NSTextView (INDSelectionHighlight)

+ (void)load
{
	INDSwizzle(self, @selector(setSelectedRange:affinity:stillSelecting:), @selector(ind_setSelectedRange:affinity:stillSelecting:));
}

- (void)ind_highlightSelectedTextInRange:(NSRange)range drawActive:(BOOL)active
{
	NSColor *selectedColor = nil;
	if (active) {
		selectedColor = self.selectedTextAttributes[NSBackgroundColorAttributeName] ?: NSColor.selectedTextBackgroundColor;
	} else {
		selectedColor = IND_DISABLED_SELECTED_TEXT_BG_COLOR;
	}
	[self.textStorage beginEditing];
	[self.textStorage removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, self.textStorage.length)];
	[self.textStorage addAttribute:NSBackgroundColorAttributeName value:selectedColor range:range];
	[self.textStorage endEditing];
	[self setNeedsDisplay:YES];
}

- (void)ind_setSelectedRange:(NSRange)charRange affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelectingFlag
{
	if (self.ind_fixSelectionHighlight) {
		if (self.ind_backgroundColorRanges == nil) {
			[self ind_backgroundColorRanges];
		}
		[self ind_highlightSelectedTextInRange:charRange drawActive:YES];
	} else {
		[self ind_setSelectedRange:charRange affinity:affinity stillSelecting:stillSelectingFlag];
	}
}

- (void)ind_backupBackgroundColorState
{
	NSMutableArray *ranges = [NSMutableArray array];
	NSString *attribute = NSBackgroundColorAttributeName;
	[self.textStorage enumerateAttribute:attribute inRange:NSMakeRange(0, self.textStorage.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
		INDAttributeRange *attrRange = [[INDAttributeRange alloc] initWithAttribute:attribute value:value range:range];
		[ranges addObject:attrRange];
	}];
	self.ind_backgroundColorRanges = ranges;
}

- (void)ind_restoreBackgroundColorState
{
	NSArray *ranges = self.ind_backgroundColorRanges;
	for (INDAttributeRange *range in ranges) {
		[self.textStorage addAttribute:range.attribute value:range.value range:range.range];
	}
	self.ind_backgroundColorRanges = nil;
}

- (void)setInd_fixSelectionHighlight:(BOOL)ind_fixSelectionHighlight
{
	objc_setAssociatedObject(self, INDFixSelectionHighlightKey, @(ind_fixSelectionHighlight), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (!ind_fixSelectionHighlight) {
		[self ind_restoreBackgroundColorState];
	}
}

- (BOOL)ind_fixSelectionHighlight
{
	return [objc_getAssociatedObject(self, INDFixSelectionHighlightKey) boolValue];
}

- (void)setInd_backgroundColorRanges:(NSArray *)ind_backgroundColorRanges
{
	objc_setAssociatedObject(self, INDBackgroundColorRangesKey, ind_backgroundColorRanges, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSArray *)ind_backgroundColorRanges
{
	return objc_getAssociatedObject(self, INDBackgroundColorRangesKey);
}

@end

@interface INDTextViewSelectionRange : NSObject
@property (nonatomic, copy, readonly) NSString *textViewIdentifier;
@property (nonatomic, assign, readonly) NSRange range;
@property (nonatomic, copy, readonly) NSAttributedString *attributedText;
@end

@implementation INDTextViewSelectionRange

- (id)initWithTextView:(NSTextView *)textView selectedRange:(NSRange)range
{
	if ((self = [super init])) {
		_textViewIdentifier = [textView.ind_uniqueIdentifier copy];
		_range = range;
		_attributedText = [[textView.attributedString attributedSubstringFromRange:range] copy];
	}
	return self;
}

@end

@interface INDTextViewSelectionSession : NSObject
@property (nonatomic, copy, readonly) NSString *textViewIdentifier;
@property (nonatomic, assign, readonly) NSUInteger characterIndex;
@property (nonatomic, strong, readonly) NSDictionary *selectionRanges;
@property (nonatomic, assign) NSPoint windowPoint;
- (void)addSelectionRange:(INDTextViewSelectionRange *)range;
- (void)removeSelectionRangeForTextView:(NSTextView *)textView;
@end

@implementation INDTextViewSelectionSession {
	NSMutableDictionary *_selectionRanges;
}
@synthesize selectionRanges = _selectionRanges;

- (id)initWithTextView:(NSTextView *)textView event:(NSEvent *)event
{
	if ((self = [super init])) {
		_textViewIdentifier = [textView.ind_uniqueIdentifier copy];
		_characterIndex = INDCharacterIndexForTextViewEvent(event, textView);
		_selectionRanges = [NSMutableDictionary dictionary];
		_windowPoint = event.locationInWindow;
	}
	return self;
}

- (void)addSelectionRange:(INDTextViewSelectionRange *)range
{
	NSParameterAssert(range.textViewIdentifier);
	_selectionRanges[range.textViewIdentifier] = range;
}

- (void)removeSelectionRangeForTextView:(NSTextView *)textView
{
	NSParameterAssert(textView.ind_uniqueIdentifier);
	[_selectionRanges removeObjectForKey:textView.ind_uniqueIdentifier];
}

@end

@interface INDSequentialTextSelectionManager ()
@property (nonatomic, strong, readonly) NSMutableDictionary *textViews;
@property (nonatomic, strong, readonly) NSMutableOrderedSet *sortedTextViews;
@property (nonatomic, strong) INDTextViewSelectionSession *currentSession;
@property (nonatomic, strong) NSAttributedString *cachedAttributedText;
@property (nonatomic, strong) id eventMonitor;
@end

@implementation INDSequentialTextSelectionManager

#pragma mark - Iniialization

- (id)init
{
	if ((self = [super init])) {
		_textViews = [NSMutableDictionary dictionary];
		_sortedTextViews = [NSMutableOrderedSet orderedSet];
		_eventMonitor = [self addLocalEventMonitor];
	}
	return self;
}

#pragma mark - Cleanup

- (void)dealloc
{
	[NSEvent removeMonitor:_eventMonitor];
}

#pragma mark - Events

- (BOOL)handleLeftMouseDown:(NSEvent *)event
{
	// Allow for correct handling of double clicks on text views.
	if (event.clickCount > 1) return NO;
	
	NSTextView *textView = [self validTextViewForEvent:event];
	
	// Ignore if the text view is not "owned" by this manager, or if it is being
	// edited at the time of this event.
	if (textView == nil || textView.window.firstResponder == textView) return NO;
	
	[self endSession];
	self.currentSession = [[INDTextViewSelectionSession alloc] initWithTextView:textView event:event];
	return YES;
}

- (BOOL)handleLeftMouseDragged:(NSEvent *)event
{
	if (self.currentSession == nil) return NO;
	NSTextView *textView = [self validTextViewForEvent:event];
	if (textView == nil) return YES;
	[textView.window makeFirstResponder:textView];
	
	NSSelectionAffinity affinity = (event.locationInWindow.y < self.currentSession.windowPoint.y) ? NSSelectionAffinityDownstream : NSSelectionAffinityUpstream;
	self.currentSession.windowPoint = event.locationInWindow;
	
	NSUInteger current;
	NSString *identifier = self.currentSession.textViewIdentifier;
	if ([textView.ind_uniqueIdentifier isEqualTo:identifier]) {
		current = self.currentSession.characterIndex;
	} else {
		NSUInteger start = [self.sortedTextViews indexOfObject:self.textViews[identifier]];
		NSUInteger end = [self.sortedTextViews indexOfObject:textView];
		current = (end >= start) ? 0 : textView.string.length;
	}
	NSUInteger index = INDCharacterIndexForTextViewEvent(event, textView);
	NSRange range = INDForwardRangeForIndices(index, current);
	[self setSelectionRangeForTextView:textView withRange:range affinity:affinity];
	[self processCompleteSelectionsForTargetTextView:textView affinity:affinity];
	return YES;
}

- (BOOL)handleRightMouseDown:(NSEvent *)event
{
	if (self.currentSession == nil) return NO;
	NSTextView *textView = [self validTextViewForEvent:event];
	if (textView == nil) return YES;
	
	NSMenu *menu = [self menuForEvent:event];
	[NSMenu popUpContextMenu:menu withEvent:event forView:textView];
	
	return YES;
}

- (BOOL)handleLeftMouseUp:(NSEvent *)event
{
	if (self.currentSession == nil) return NO;
	[event.window makeFirstResponder:self];
	return YES;
}

- (id)addLocalEventMonitor
{
	return [NSEvent addLocalMonitorForEventsMatchingMask:NSLeftMouseDownMask | NSLeftMouseDraggedMask | NSLeftMouseUpMask | NSRightMouseDownMask handler:^NSEvent *(NSEvent *event) {
		switch (event.type) {
			case NSLeftMouseDown:
				return [self handleLeftMouseDown:event] ? nil : event;
			case NSLeftMouseDragged:
				return [self handleLeftMouseDragged:event] ? nil : event;
			case NSLeftMouseUp:
				return [self handleLeftMouseUp:event] ? nil : event;
			case NSRightMouseDown:
				return [self handleRightMouseDown:event] ? nil : event;
			default:
				return event;
		}
	}];
}

- (NSTextView *)validTextViewForEvent:(NSEvent *)event
{
	NSView *contentView = event.window.contentView;
	NSPoint point = [contentView convertPoint:event.locationInWindow fromView:nil];
	NSView *view = [contentView hitTest:point];
	if ([view isKindOfClass:NSTextView.class]) {
		NSTextView *textView = (NSTextView *)view;
		NSString *identifier = textView.ind_uniqueIdentifier;
		return (textView.isSelectable && identifier && self.textViews[identifier]) ? textView : nil;
	}
	return nil;
}

#pragma mark - NSResponder

- (NSAttributedString *)cachedAttributedText
{
	if (_cachedAttributedText == nil) {
		_cachedAttributedText = [self buildAttributedStringForCurrentSession];
	}
	return _cachedAttributedText;
}

- (void)copy:(id)sender
{
	NSPasteboard *pboard = NSPasteboard.generalPasteboard;
	[pboard clearContents];
	[pboard writeObjects:@[self.cachedAttributedText]];
}

- (NSMenu *)buildSharingMenu
{
	NSMenu *shareMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Share", nil)];
	NSArray *services = [NSSharingService sharingServicesForItems:@[self.cachedAttributedText]];
	for (NSSharingService *service in services) {
		NSMenuItem *item = [shareMenu addItemWithTitle:service.title action:@selector(share:) keyEquivalent:@""];
		item.target = self;
		item.image = service.image;
		item.representedObject = service;
	}
	return shareMenu;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Text Actions", nil)];
	NSMenuItem *copy = [menu addItemWithTitle:NSLocalizedString(@"Copy", nil) action:@selector(copy:) keyEquivalent:@""];
	copy.target = self;
	[menu addItem:NSMenuItem.separatorItem];
	
	NSMenuItem *share = [menu addItemWithTitle:NSLocalizedString(@"Share", nil) action:nil keyEquivalent:@""];
	share.submenu = [self buildSharingMenu];
	
	return menu;
}

- (void)share:(NSMenuItem *)item
{
	NSSharingService *service = item.representedObject;
	[service performWithItems:@[self.cachedAttributedText]];
}

- (void)rehighlightSelectedRangesAsActive:(BOOL)active
{
	NSArray *ranges = self.currentSession.selectionRanges.allValues;
	for (INDTextViewSelectionRange *range in ranges) {
		NSTextView *textView = self.textViews[range.textViewIdentifier];
		[textView ind_highlightSelectedTextInRange:range.range drawActive:active];
	}
}

- (BOOL)resignFirstResponder
{
	[self rehighlightSelectedRangesAsActive:NO];
	return YES;
}

- (BOOL)becomeFirstResponder
{
	[self rehighlightSelectedRangesAsActive:YES];
	return YES;
}

#pragma mark - Selection

- (void)setSelectionRangeForTextView:(NSTextView *)textView withRange:(NSRange)range affinity:(NSSelectionAffinity)affinity
{
	if (range.location == NSNotFound || NSMaxRange(range) == 0) {
		textView.selectedRange = NSMakeRange(0, 0);
		[self.currentSession removeSelectionRangeForTextView:textView];
	} else {
		INDTextViewSelectionRange *selRange = [[INDTextViewSelectionRange alloc] initWithTextView:textView selectedRange:range];
		[self.currentSession addSelectionRange:selRange];
		[textView setSelectedRange:range affinity:affinity stillSelecting:YES];
	}
}

- (void)processCompleteSelectionsForTargetTextView:(NSTextView *)textView affinity:(NSSelectionAffinity)affinity
{
	if (self.currentSession == nil) return;
	
	NSTextView *startingView = self.textViews[self.currentSession.textViewIdentifier];
	NSUInteger start = [self.sortedTextViews indexOfObject:startingView];
	NSUInteger end = [self.sortedTextViews indexOfObject:textView];
	if (start == NSNotFound || end == NSNotFound) return;
	
	NSRange subrange = NSMakeRange(NSNotFound, 0);
	BOOL select = NO;
	NSUInteger count = self.sortedTextViews.count;
	if (end > start) {
		if (affinity == NSSelectionAffinityDownstream) {
			subrange = NSMakeRange(start, end - start);
			select = YES;
		} else if (count > end + 1) {
			subrange = NSMakeRange(end + 1, count - end - 1);
		}
	} else if (end < start) {
		if (affinity == NSSelectionAffinityUpstream) {
			subrange = NSMakeRange(end + 1, start - end);
			select = YES;
		} else {
			subrange = NSMakeRange(0, end);
		}
	}
	NSArray *subarray = nil;
	if (subrange.location == NSNotFound) {
		NSMutableOrderedSet *views = [self.sortedTextViews mutableCopy];
		[views removeObject:textView];
		subarray = views.array;
	} else {
		subarray = [self.sortedTextViews.array subarrayWithRange:subrange];
	}
	for (NSTextView *tv in subarray) {
		NSRange range;
		if (select) {
			NSRange currentRange = tv.selectedRange;
			if (affinity == NSSelectionAffinityDownstream) {
				range = NSMakeRange(currentRange.location, tv.string.length - currentRange.location);
			} else {
				range = NSMakeRange(0, NSMaxRange(currentRange) ?: tv.string.length);
			}
		} else {
			range = NSMakeRange(0, 0);
		}
		[self setSelectionRangeForTextView:tv withRange:range affinity:affinity];
	}
}

- (void)endSession
{
	for (NSTextView *textView in self.textViews.allValues) {
		textView.selectedRange = NSMakeRange(0, 0);
		[textView ind_restoreBackgroundColorState];
	}
	self.currentSession = nil;
	self.cachedAttributedText = nil;
}

#pragma mark - Text

- (NSAttributedString *)buildAttributedStringForCurrentSession
{
	if (self.currentSession == nil) return nil;
	
	NSDictionary *ranges = self.currentSession.selectionRanges;
	NSMutableArray *keys = [ranges.allKeys mutableCopy];
	NSComparator textViewComparator = self.textViewComparator;
	[keys sortUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
		return textViewComparator(self.textViews[obj1], self.textViews[obj2]);
	}];
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] init];
	[string beginEditing];
	[keys enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop) {
		INDTextViewSelectionRange *range = ranges[key];
		[string appendAttributedString:range.attributedText];
		if (string.length && idx != keys.count - 1) {
			NSDictionary *attributes = [string attributesAtIndex:string.length - 1 effectiveRange:NULL];
			NSAttributedString *newline = [[NSAttributedString alloc] initWithString:@"\n" attributes:attributes];
			[string appendAttributedString:newline];
		}
	}];
	[string endEditing];
	return string;
}

#pragma mark - Registration

- (void)registerTextView:(NSTextView *)textView withUniqueIdentifier:(NSString *)identifier
{
	NSParameterAssert(identifier);
	NSParameterAssert(textView);
	
	[self unregisterTextView:textView];
	textView.ind_uniqueIdentifier = identifier;
	textView.ind_fixSelectionHighlight = YES;
	if (self.currentSession) {
		INDTextViewSelectionRange *range = self.currentSession.selectionRanges[identifier];
		if (range) {
			textView.selectedRange = range.range;
		}
	}
	self.textViews[identifier] = textView;
	
	[self.sortedTextViews addObject:textView];
	[self sortTextViews];
}

- (NSComparator)textViewComparator
{
	return ^NSComparisonResult(NSTextView *obj1, NSTextView *obj2) {
		// Convert to window coordinates to normalize coordinate flipped-ness
		NSRect frame1 = [obj1 convertRect:obj1.bounds toView:nil];
		NSRect frame2 = [obj2 convertRect:obj2.bounds toView:nil];
		
		CGFloat y1 = NSMinY(frame1);
		CGFloat y2 = NSMinY(frame2);
		
		if (y1 > y2) {
			return NSOrderedAscending;
		} else if (y1 < y2) {
			return NSOrderedDescending;
		} else {
			return NSOrderedSame;
		}
	};
}

- (void)sortTextViews
{
	[self.sortedTextViews sortUsingComparator:self.textViewComparator];
}

- (void)unregisterTextView:(NSTextView *)textView
{
	if (textView.ind_uniqueIdentifier == nil) return;
	[self.textViews removeObjectForKey:textView.ind_uniqueIdentifier];
	[self.sortedTextViews removeObject:textView];
	[self sortTextViews];
	
	textView.ind_fixSelectionHighlight = NO;
	textView.ind_uniqueIdentifier = nil;
}

- (void)unregisterAllTextViews
{
	[self.textViews removeAllObjects];
	[self.sortedTextViews removeAllObjects];
}

@end
