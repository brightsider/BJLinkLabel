/***********************************************************************************
 *
 * The MIT License (MIT)
 *
 * Copyright (c) 2013 Benjamin Jackson
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 ***********************************************************************************/

#import "BJLinkLabel.h"


#pragma mark - Private Interface

@interface BJLinkLabel()

// Used to control layout of glyphs and rendering
@property (nonatomic, retain) NSLayoutManager *layoutManager;

// Specifies the space in which to render text
@property (nonatomic, retain) NSTextContainer *textContainer;

// Backing storage for text that is rendered by the layout manager
@property (nonatomic, retain) NSTextStorage *textStorage;

// Dictionary of detected links and their ranges in the text
@property (nonatomic, copy) NSArray *linkRanges;

// State used to trag if the user has dragged during a touch
@property (nonatomic, assign) BOOL isTouchMoved;

// During a touch, range of text that is displayed as selected
@property (nonatomic, assign) NSRange selectedRange;

@end


#pragma mark - Implementation

@implementation BJLinkLabel

#pragma mark - Construction

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self setupTextSystem];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        [self setupTextSystem];
    }
    return self;
}

// Common initialisation. Must be done once during construction.
- (void)setupTextSystem
{
    // Create a text container and set it up to match our label properties
    self.textContainer = [[NSTextContainer alloc] init];
    self.textContainer.lineFragmentPadding = 0;
    self.textContainer.maximumNumberOfLines = self.numberOfLines;
    self.textContainer.lineBreakMode = self.lineBreakMode;
    self.textContainer.size = self.frame.size;
    
    // Create a layout manager for rendering
    self.layoutManager = [[NSLayoutManager alloc] init];
    self.layoutManager.delegate = self;
    [self.layoutManager addTextContainer:self.textContainer];
    
    // Attach the layou manager to the container and storage
    [self.textContainer setLayoutManager:self.layoutManager];
    
    // Make sure user interaction is enabled so we can accept touches
    self.userInteractionEnabled = YES;
    
    // Don't go via public setter as this will have undesired side effect
    _automaticLinkDetectionEnabled = YES;
        
    // Establish the text store with our current text
    [self updateTextStoreWithAttributedString:self.attributedText];
    
    // Attach a default detection handler to help with debugging
    self.linkTapHandler = ^(NSString *string, NSRange range) {
        NSLog(@"Default handler for label: %@, (%lu, %lu)", string, (unsigned long)range.location, (unsigned long)range.length);
    };
}

#pragma mark - Text and Style management

- (void)addLinkWithURL:(NSURL *)URL atRange:(NSRange)range {
    NSMutableAttributedString *attributedString = [self.attributedText mutableCopy];
    NSDictionary *attributes = @{ NSForegroundColorAttributeName : self.tintColor };
    if (!self.linkRanges) {
        self.linkRanges = [[NSArray alloc] init];
    }
    self.linkRanges = [self.linkRanges arrayByAddingObjectsFromArray:@[@{ @"range" : [NSValue valueWithRange:range],
                                                                          @"link" : URL }]];
    [attributedString addAttributes:attributes range:range];
    self.attributedText = attributedString;
}

- (NSDictionary *)getLinkAtLocation:(CGPoint)location
{
    // Do nothing if we have no text
    if (self.textStorage.string.length == 0)
    {
        return nil;
    }
    
    // Work out the offset of the text in the view
    CGPoint textOffset;
    NSRange glyphRange = [self.layoutManager glyphRangeForTextContainer:self.textContainer];
    textOffset = [self calcTextOffsetForGlyphRange:glyphRange];
    
    // Get the touch location and use text offset to convert to text cotainer coords
    location.x -= textOffset.x;
    location.y -= textOffset.y;
    
    NSUInteger touchedChar = [self.layoutManager glyphIndexForPoint:location inTextContainer:self.textContainer];
    
    // If the touch is in white space after the last glyph on the line we don't
    // count it as a hit on the text
    NSRange lineRange;
    CGRect lineRect = [self.layoutManager lineFragmentUsedRectForGlyphAtIndex:touchedChar effectiveRange:&lineRange];
    if (CGRectContainsPoint(lineRect, location) == NO)
    {
        return nil;
    }
    
    // Find the word that was touched and call the detection block
    for (NSDictionary *dictionary in self.linkRanges)
    {
        NSRange range = [[dictionary objectForKey:@"range"] rangeValue];
        
        if ((touchedChar >= range.location) && touchedChar < (range.location + range.length))
        {
            return dictionary;
        }
    }
    
    return nil;
}

// Applies background colour to selected range. Used to highlight touched links
- (void)setSelectedRange:(NSRange)range
{
    // Remove the current selection if the selection is changing
    if (self.selectedRange.length && !NSEqualRanges(self.selectedRange, range))
    {
        if (self.selectedLinkBackgroundColour) {
            [self.textStorage removeAttribute:NSBackgroundColorAttributeName
                                        range:self.selectedRange];
        }
        [self.textStorage addAttribute:NSForegroundColorAttributeName
                                 value:self.tintColor
                                 range:self.selectedRange];
    }
    
    // Apply the new selection to the text
    if (range.length)
    {
        if (self.selectedLinkBackgroundColour) {
            [self.textStorage addAttribute:NSBackgroundColorAttributeName
                                     value:self.selectedLinkBackgroundColour
                                     range:range];
        }
        if (self.selectedLinkColour) {
            [self.textStorage addAttribute:NSForegroundColorAttributeName
                                     value:self.selectedLinkColour
                                     range:range];
        }
    }
    
    // Save the new range
    _selectedRange = range;
    
    [self setNeedsDisplay];
}

- (void)setNumberOfLines:(NSInteger)numberOfLines
{
    [super setNumberOfLines:numberOfLines];
    
    self.textContainer.maximumNumberOfLines = numberOfLines;
}

- (void)setAttributedText:(NSAttributedString *)attributedText
{
    // Pass the text to the super class first
    [super setAttributedText:attributedText];

    if (![attributedText.string isEqualToString:self.attributedText.string]) {
        self.linkRanges = nil;
    }
    
    [self updateTextStoreWithAttributedString:attributedText];
}

#pragma mark - Text Storage Management

- (void)updateTextStoreWithAttributedString:(NSAttributedString *)attributedString
{
    if (attributedString.length != 0)
    {
        attributedString = [BJLinkLabel sanitizeAttributedString:attributedString];
    }
    
    if (self.textStorage)
    {
        // Set the string on the storage
        [self.textStorage setAttributedString:attributedString];
    }
    else
    {
        // Create a new text storage and attach it correctly to the layout manager
        self.textStorage = [[NSTextStorage alloc] initWithAttributedString:attributedString];
        [self.textStorage addLayoutManager:self.layoutManager];
        [self.layoutManager setTextStorage:self.textStorage];
    }
}

#pragma mark - Layout and Rendering

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines
{
    // Use our text container to calculate the bounds required. First save our
    // current text container setup
    CGSize savedTextContainerSize = self.textContainer.size;
    NSInteger savedTextContainerNumberOfLines = self.textContainer.maximumNumberOfLines;
    
    // Apply the new potential bounds and number of lines
    self.textContainer.size = bounds.size;
    self.textContainer.maximumNumberOfLines = numberOfLines;
    
    // Measure the text with the new state
    CGRect textBounds;
    @try
    {
        NSRange glyphRange = [self.layoutManager glyphRangeForTextContainer:self.textContainer];
        textBounds = [self.layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:self.textContainer];
        
        // Position the bounds and round up the size for good measure
        textBounds.origin = bounds.origin;
        textBounds.size.width = ceilf(textBounds.size.width);
        textBounds.size.height = ceilf(textBounds.size.height);
    }
    @finally
    {
        // Restore the old container state before we exit under any circumstances
        self.textContainer.size = savedTextContainerSize;
        self.textContainer.maximumNumberOfLines = savedTextContainerNumberOfLines;
    }
    
    return textBounds;
}

- (void)drawTextInRect:(CGRect)rect
{
    // Don't call super implementation. Might want to uncomment this out when
    // debugging layout and rendering problems.
    //        [super drawTextInRect:rect];
    
    // Calculate the offset of the text in the view
    CGPoint textOffset;
    NSRange glyphRange = [self.layoutManager glyphRangeForTextContainer:self.textContainer];
    textOffset = [self calcTextOffsetForGlyphRange:glyphRange];
    
    // Drawing code
    [self.layoutManager drawBackgroundForGlyphRange:glyphRange atPoint:textOffset];
    [self.layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:textOffset];
}

// Returns the XY offset of the range of glyphs from the view's origin
- (CGPoint)calcTextOffsetForGlyphRange:(NSRange)glyphRange
{
    CGPoint textOffset = CGPointZero;
    
    CGRect textBounds = [self.layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:self.textContainer];
    CGFloat paddingHeight = (self.bounds.size.height - textBounds.size.height) / 2.0f;
    if (paddingHeight > 0)
    {
        textOffset.y = paddingHeight;
    }
    
    return textOffset;
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    self.textContainer.size = self.bounds.size;
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];
    self.textContainer.size = self.bounds.size;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    // Update our container size when the view frame changes
    self.textContainer.size = self.bounds.size;
}


#pragma mark - Interactions

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    self.isTouchMoved = NO;
    
    // Get the info for the touched link if there is one
    NSDictionary *touchedLink;
    CGPoint touchLocation = [[touches anyObject] locationInView:self];
    touchedLink = [self getLinkAtLocation:touchLocation];
    
    if (touchedLink)
    {
        self.selectedRange = [[touchedLink objectForKey:@"range"] rangeValue];
    }
    else
    {
        [super touchesBegan:touches withEvent:event];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    
    self.isTouchMoved = YES;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    
    // If the user dragged their finger we ignore the touch
    if (self.isTouchMoved)
    {
        self.selectedRange = NSMakeRange(0, 0);
        
        return;
    }
    
    // Get the info for the touched link if there is one
    NSDictionary *touchedLink;
    CGPoint touchLocation = [[touches anyObject] locationInView:self];
    touchedLink = [self getLinkAtLocation:touchLocation];
    
    if (touchedLink)
    {
        NSRange range = [[touchedLink objectForKey:@"range"] rangeValue];
        NSString *touchedSubstring = [touchedLink objectForKey:@"link"];
        self.linkTapHandler(touchedSubstring, range);
    }
    else
    {
        [super touchesBegan:touches withEvent:event];
    }
    
    self.selectedRange = NSMakeRange(0, 0);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    
    // Make sure we don't leave a selection when the touch is cancelled
    self.selectedRange = NSMakeRange(0, 0);
}


#pragma mark - Layout manager delegate

-(BOOL)layoutManager:(NSLayoutManager *)layoutManager shouldBreakLineByWordBeforeCharacterAtIndex:(NSUInteger)charIndex
{
    // Don't allow line breaks inside URLs
    NSRange range;
    NSURL *linkURL = [layoutManager.textStorage attribute:NSLinkAttributeName
                                                  atIndex:charIndex
                                           effectiveRange:&range];
    
    return !(linkURL && (charIndex > range.location) && (charIndex <= NSMaxRange(range)));
}

+ (NSAttributedString *)sanitizeAttributedString:(NSAttributedString *)attributedString
{
    // Setup paragraph alignement properly. IB applies the line break style
    // to the attributed string. The problem is that the text container then
    // breaks at the first line of text. If we set the line break to wrapping
    // then the text container defines the break mode and it works.
    // NOTE: This is either an Apple bug or something I've misunderstood.
    
    // Get the current paragraph style. IB only allows a single paragraph so
    // getting the style of the first char is fine.
    NSRange range;
    NSParagraphStyle *paragraphStyle = [attributedString attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:&range];
    
    if (paragraphStyle == nil)
    {
        return attributedString;
    }
    
    // Remove the line breaks
    NSMutableParagraphStyle *mutableParagraphStyle = [paragraphStyle mutableCopy];
    mutableParagraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    
    // Apply new style
    NSMutableAttributedString *restyled = [[NSMutableAttributedString alloc] initWithAttributedString:attributedString];
    [restyled addAttribute:NSParagraphStyleAttributeName value:mutableParagraphStyle range:NSMakeRange(0, restyled.length)];
    
    return restyled;
}


@end