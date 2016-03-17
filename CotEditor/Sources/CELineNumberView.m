/*
 
 CELineNumberView.m
 
 CotEditor
 http://coteditor.com
 
 Created by nakamuxu on 2005-03-30.
 
 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
 © 2014-2015 1024jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 */

@import CoreText;
#import "CELineNumberView.h"
#import "CETextViewProtocol.h"
#import "Constants.h"


static const NSUInteger kMinNumberOfDigits = 3;
static const CGFloat kMinVerticalThickness = 32.0;
static const CGFloat kMinHorizontalThickness = 20.0;
static const CGFloat  kLineNumberPadding = 3.0;


@interface CELineNumberView ()

@property (nonatomic, nullable) NSTimer *draggingTimer;

@end




#pragma mark -

@implementation CELineNumberView

static const NSString *LineNumberFontName;


#pragma mark Superclass Methods

// ------------------------------------------------------
/// initialize class
+ (void)initialize
// ------------------------------------------------------
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *defaultFontName = [[NSUserDefaults standardUserDefaults] stringForKey:CEDefaultLineNumFontNameKey];
        NSFont *font = [NSFont fontWithName:defaultFontName size:0] ? : [NSFont paletteFontOfSize:0];
        LineNumberFontName = [font fontName];
    });
}


// ------------------------------------------------------
/// initialize instance
- (nonnull instancetype)initWithScrollView:(nullable NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation
// ------------------------------------------------------
{
    self = [super initWithScrollView:scrollView orientation:orientation];
    if (self) {
        [self setClientView:[scrollView documentView]];
    }
    return self;
}


// ------------------------------------------------------
/// setup initial size
- (void)viewDidMoveToSuperview
// ------------------------------------------------------
{
    [super viewDidMoveToSuperview];
    
    CGFloat thickness = [self orientation] == NSHorizontalRuler ? kMinHorizontalThickness : kMinVerticalThickness;
    [self setRuleThickness:thickness];
}


// ------------------------------------------------------
/// draw background
- (void)drawRect:(NSRect)dirtyRect
// ------------------------------------------------------
{
    NSColor *counterColor = [[[self textView] theme] isDarkTheme] ? [NSColor whiteColor] : [NSColor blackColor];
    NSColor *textColor = [[[self textView] theme] weakTextColor];
    
    // fill background
    [[counterColor colorWithAlphaComponent:0.08] set];
    [NSBezierPath fillRect:dirtyRect];
    
    // draw frame border (1px)
    [[textColor colorWithAlphaComponent:0.3] set];
    switch ([self orientation]) {
        case NSVerticalRuler:
            [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(dirtyRect) - 0.5, NSMaxY(dirtyRect))
                                      toPoint:NSMakePoint(NSMaxX(dirtyRect) - 0.5, NSMinY(dirtyRect))];
            break;
            
        case NSHorizontalRuler:
            [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(dirtyRect), NSMaxY(dirtyRect) - 0.5)
                                      toPoint:NSMakePoint(NSMaxX(dirtyRect), NSMaxY(dirtyRect) - 0.5)];
            break;
    }
    
    [self drawHashMarksAndLabelsInRect:dirtyRect];
}


// ------------------------------------------------------
/// draw line numbers
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect
// ------------------------------------------------------
{
    NSString *string = [[self textView] string];
    
    if ([string length] == 0) { return; }
    
    NSLayoutManager *layoutManager = [[self textView] layoutManager];
    NSColor *textColor = [[[self textView] theme] weakTextColor];
    
    // set graphics context
    CGContextRef context = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(context);

    // setup font
    CGFloat masterFontSize = [[[self textView] font] pointSize];
    CGFloat fontSize = round(0.9 * masterFontSize);
    CTFontRef font = CTFontCreateWithName((CFStringRef)LineNumberFontName, fontSize, nil);
    
    CGFloat tickLength = ceil(fontSize / 3);
    
    CGFontRef cgFont = CTFontCopyGraphicsFont(font, NULL);
    CGContextSetFont(context, cgFont);
    CGContextSetFontSize(context, fontSize);
    CGContextSetFillColorWithColor(context, [textColor CGColor]);
    CFRelease(cgFont);
    
    // prepare glyphs
    CGGlyph wrappedMarkGlyph;
    const unichar dash = '-';
    CTFontGetGlyphsForCharacters(font, &dash, &wrappedMarkGlyph, 1);
    
    CGGlyph digitGlyphs[10];
    const unichar numbers[10] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'};
    CTFontGetGlyphsForCharacters(font, numbers, digitGlyphs, 10);
    
    // calc character width as monospaced font
    CGSize advance;
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &digitGlyphs[8], &advance, 1);  // use '8' to get width
    CGFloat charWidth = advance.width;
    
    // prepare frame width
    CGFloat ruleThickness = [self ruleThickness];
    
    // adjust text drawing coordinate
    NSPoint relativePoint = [self convertPoint:NSZeroPoint fromView:[self textView]];
    NSPoint inset = [[self textView] textContainerOrigin];
    CGFloat diff = masterFontSize - fontSize;
    CGFloat ascent = CTFontGetAscent(font);
    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformScale(transform, 1.0, -1.0);  // flip
    transform = CGAffineTransformTranslate(transform, -kLineNumberPadding, -relativePoint.y - inset.y - diff - ascent);
    CGContextSetTextMatrix(context, transform);
    CFRelease(font);
    
    // add enough buffer to avoid broken drawing on Mountain Lion (10.8) with scroller (2015-07)
    NSRect visibleRect = [[self scrollView] documentVisibleRect];
    visibleRect.size.height += fontSize;
    
    // get glyph range which line number should be drawn
    NSRange visibleGlyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect
                                                         inTextContainer:[[self textView] textContainer]];
    
    BOOL isVerticalText = [self orientation] == NSHorizontalRuler;
    NSUInteger tailGlyphIndex = [layoutManager glyphIndexForCharacterAtIndex:[string length]];
    
    // draw line number block
    CGGlyph *digitGlyphsPtr = digitGlyphs;
    void (^draw_number)(NSUInteger, NSUInteger, CGFloat, BOOL) = ^(NSUInteger lineNumber, NSUInteger lastLineNumber, CGFloat y, BOOL drawsNumber)
    {
        if (isVerticalText) {
            // translate y position to horizontal axis
            y += relativePoint.x - masterFontSize / 2 - inset.y;
            
            // draw ticks on vertical text
            CGFloat x = round(y) - 0.5;
            CGContextMoveToPoint(context, x, ruleThickness);
            CGContextAddLineToPoint(context, x, ruleThickness - tickLength);
        }
        
        // draw line number
        if (drawsNumber) {
            NSUInteger digit = numberOfDigits(lineNumber);
            
            // calculate base position
            CGPoint position;
            if (isVerticalText) {
                position = CGPointMake(ceil(y + charWidth * (digit + 1) / 2), ruleThickness + tickLength - 2);
            } else {
                position = CGPointMake(ruleThickness, y);
            }
            
            // get glyphs and positions
            CGGlyph glyphs[digit];
            CGPoint positions[digit];
            for (NSUInteger i = 0; i < digit; i++) {
                position.x -= charWidth;
                
                positions[i] = position;
                glyphs[i] = digitGlyphsPtr[numberAt(i, lineNumber)];
            }
            
            CGContextShowGlyphsAtPositions(context, glyphs, positions, digit);  // draw line number
        }
    };
    
    // counters
    NSUInteger glyphCount = visibleGlyphRange.location;
    NSUInteger lineNumber = 1;
    NSUInteger lastLineNumber = 0;
    
    // count lines until visible
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\n" options:0 error:nil];
    lineNumber += [regex numberOfMatchesInString:string options:0
                                           range:NSMakeRange(0, [layoutManager characterIndexForGlyphAtIndex:visibleGlyphRange.location])];
    
    // draw visible line numbers
    for (NSUInteger glyphIndex = visibleGlyphRange.location; glyphIndex < NSMaxRange(visibleGlyphRange); lineNumber++) { // count "real" lines
        NSUInteger charIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
        glyphIndex = NSMaxRange([layoutManager glyphRangeForCharacterRange:[string lineRangeForRange:NSMakeRange(charIndex, 0)]
                                                      actualCharacterRange:NULL]);
        
        while (glyphCount < glyphIndex) { // handle wrapped lines
            NSRange range;
            NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphCount effectiveRange:&range withoutAdditionalLayout:YES];
            CGFloat y = -NSMinY(lineRect);
            
            if (lastLineNumber == lineNumber) {  // wrapped line
                if (!isVerticalText) {
                    CGPoint position = CGPointMake(ruleThickness - charWidth, y);
                    CGContextShowGlyphsAtPositions(context, &wrappedMarkGlyph, &position, 1);  // draw wrapped mark
                }
                
            } else {  // new line
                BOOL drawsNumber = (!isVerticalText || lineNumber % 5 == 0 || lineNumber == 1);
                draw_number(lineNumber, lastLineNumber, y, drawsNumber);
            }
            
            glyphCount = NSMaxRange(range);
            
            // draw last line number anyway
            if (isVerticalText &&  // vertical text
                lastLineNumber != lineNumber &&  // new line
                isVerticalText && lineNumber != 1 && lineNumber % 5 != 0 &&  // not yet drawn
                tailGlyphIndex == glyphIndex &&  // last line
                ![layoutManager extraLineFragmentTextContainer])  // no extra number
            {
                draw_number(lineNumber, lastLineNumber, y, YES);
            }
            
            lastLineNumber = lineNumber;
        }
    }
    
    // draw the last "extra" line number
    if ([layoutManager extraLineFragmentTextContainer]) {
        NSRect lineRect = [layoutManager extraLineFragmentUsedRect];
        CGFloat y = -NSMinY(lineRect);
        
        draw_number(lineNumber, lastLineNumber, y, YES);
    }
    
    // draw vertical text tics
    if (isVerticalText) {
        CGContextSetStrokeColorWithColor(context, [[textColor colorWithAlphaComponent:0.6] CGColor]);
        CGContextStrokePath(context);
    }
    
    CGContextRestoreGState(context);
    
    // adjust thickness
    CGFloat requiredThickness;
    if (isVerticalText) {
        requiredThickness = MAX(fontSize + tickLength + 2 * kLineNumberPadding, kMinHorizontalThickness);
    } else {
        NSUInteger length = MAX(numberOfDigits(lineNumber), kMinNumberOfDigits);
        requiredThickness = MAX(length * charWidth + 3 * kLineNumberPadding, kMinVerticalThickness);
    }
    [self setRuleThickness:ceil(requiredThickness)];
}


// ------------------------------------------------------
/// make background transparent
- (BOOL)isOpaque
// ------------------------------------------------------
{
    return NO;
}


// ------------------------------------------------------
/// remove extra thickness
- (CGFloat)requiredThickness
// ------------------------------------------------------
{
    if ([self orientation] == NSHorizontalRuler) {
        return [self ruleThickness];
    }
    return MAX(kMinVerticalThickness, [self ruleThickness]);
}


// ------------------------------------------------------
/// start selecting correspondent lines in text view with drag / click event
- (void)mouseDown:(nonnull NSEvent *)theEvent
// ------------------------------------------------------
{
    // get start point
    NSPoint point = [[self window] convertRectToScreen:NSMakeRect([theEvent locationInWindow].x,
                                                                  [theEvent locationInWindow].y, 0, 0)].origin;
    NSUInteger index = [[self textView] characterIndexForPoint:point];
    
    [self selectLines:nil];  // for single click event
    
    // repeat while dragging
    [self setDraggingTimer:[NSTimer scheduledTimerWithTimeInterval:0.05
                                                            target:self
                                                          selector:@selector(selectLines:)
                                                          userInfo:@(index)
                                                           repeats:YES]];
}


// ------------------------------------------------------
/// end selecting correspondent lines in text view with drag event
- (void)mouseUp:(nonnull NSEvent *)theEvent
// ------------------------------------------------------
{
    [[self draggingTimer] invalidate];
    [self setDraggingTimer:nil];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// return client view casting to textView
- (nullable NSTextView<CETextViewProtocol> *)textView
// ------------------------------------------------------
{
    return (NSTextView<CETextViewProtocol> *)[self clientView];
}


// ------------------------------------------------------
/// select lines while dragging event
- (void)selectLines:(nullable NSTimer *)timer
// ------------------------------------------------------
{
    NSTextView *textView = [self textView];
    NSPoint point = [NSEvent mouseLocation];  // screen based point
    
    // scroll text view if needed
    CGFloat y = [self convertPoint:[[self window] convertRectFromScreen:NSMakeRect(point.x, point.y, 0, 0)].origin
                          fromView:nil].y;
    if (y < 0) {
        [textView scrollLineUp:nil];
    } else if (y > NSHeight([self bounds])) {
        [textView scrollLineDown:nil];
    }
    
    // select lines
    NSUInteger currentIndex = [textView characterIndexForPoint:point];
    NSUInteger clickedIndex = timer ? [[timer userInfo] unsignedIntegerValue] : currentIndex;
    NSRange range = [[textView string] lineRangeForRange:NSMakeRange(MIN(currentIndex, clickedIndex),
                                                                     currentIndex - clickedIndex)];
    [textView setSelectedRange:range];
}



#pragma mark Private C Functions

/// digits of input number
unsigned int numberOfDigits(int number) { return (unsigned int)log10(number) + 1; }

/// number at the desired place of input number
unsigned int numberAt(int place, int number) { return (number % (int)pow(10, place + 1)) / pow(10, place); }

@end
