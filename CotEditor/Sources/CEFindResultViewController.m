/*
 
 CEFindResultViewController.m
 
 CotEditor
 http://coteditor.com
 
 Created by 1024jp on 2015-01-04.

 ------------------------------------------------------------------------------
 
 © 2015 1024jp
 
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

#import <OgreKit/OgreKit.h>
#import "CEFindResultViewController.h"

/// the maximum number of characters to add to the left of the matched string
static const int kMaxLeftMargin = 64;
/// maximal number of characters for the result line
static const int kMaxMatchedStringLength = 256;


// hack OgreKit's private OgreTextViewFindResult class (cf. OgreTextViewFindResult.h in OgreKit framewrok source)
@protocol OgreTextViewFindResultInterface <NSObject>

// index番目にマッチした文字列のある行番号
- (NSNumber*)lineOfMatchedStringAtIndex:(unsigned)index;
// index番目にマッチした文字列
- (NSAttributedString *)matchedStringAtIndex:(unsigned)index;
// index番目にマッチした文字列を選択・表示する
- (BOOL)showMatchedStringAtIndex:(unsigned)index;
// index番目にマッチした文字列を選択する
- (BOOL)selectMatchedStringAtIndex:(unsigned)index;

@end


#pragma mark -

@interface CEFindResultViewController () <OgreTextFindResultDelegateProtocol>

@property (nonatomic, nullable, copy) NSString *resultMessage;
@property (nonatomic, nullable, copy) NSString *findString;
@property (nonatomic, nullable, copy) NSString *documentName;
@property (nonatomic) NSUInteger count;
@property (nonatomic) BOOL enableLiveUpdate;

@property (nonatomic, nullable, weak) IBOutlet NSTableView *tableView;

@end




#pragma mark -

@implementation CEFindResultViewController

#pragma mark Superclass Methods

// ------------------------------------------------------
/// clean up
- (void)dealloc
// ------------------------------------------------------
{
    [[self result] setDelegate:nil];
}



#pragma mark Public Accessors

// ------------------------------------------------------
/// setter for result property
- (void)setResult:(OgreTextFindResult *)result
// ------------------------------------------------------
{
    [result setMaximumLeftMargin:kMaxLeftMargin];
    [result setMaximumMatchedStringLength:kMaxMatchedStringLength];
    [result setDelegate:self];
    
    _result = result;
    
    [self reloadResult];
}



#pragma mark Protocol

//=======================================================
// NSTableViewDataSource Protocol
//=======================================================

// ------------------------------------------------------
/// return number of row (required)
- (NSInteger)numberOfRowsInTableView:(nonnull NSTableView *)tableView
// ------------------------------------------------------
{
    // [note] This method `selectMatchedString` in fact just returns whether textView exists yet and do nothing else.
    BOOL existsTarget = [[self textViewResult] selectMatchedString];
    
    if ([self enableLiveUpdate] && !existsTarget) {
        return 1;
    }
    
    return [[self result] numberOfMatches];
}


// ------------------------------------------------------
/// return value of cell (required)
- (nullable id)tableView:(nonnull NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
// ------------------------------------------------------
{
    if (![self result]) { return nil; }
    
    OgreFindResultBranch<OgreTextViewFindResultInterface> *textViewResult = [self textViewResult];
    BOOL existsTarget = [textViewResult selectMatchedString];
    
    if ([[tableColumn identifier] isEqualToString:@"line"]) {
        return existsTarget ? [textViewResult lineOfMatchedStringAtIndex:row] : nil;
    } else {
        return [textViewResult matchedStringAtIndex:row];
    }
}



#pragma mark Delegate

//=======================================================
// NSTableViewDelegate  < tableView
//=======================================================

// ------------------------------------------------------
/// select matched string in text view
- (void)tableViewSelectionDidChange:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    NSTableView *tableView = [notification object];
    NSInteger row = [tableView selectedRow];
    
    if (row > [self count]) { return; }
    
    OgreFindResultBranch<OgreTextViewFindResultInterface> *result = [self textViewResult];
    
    if (![result selectMatchedString]) {
        NSBeep();
        return;
    }
    
    NSTextView *textView = [self target];
    dispatch_async(dispatch_get_main_queue(), ^{
        [result selectMatchedStringAtIndex:row];
        [textView showFindIndicatorForRange:[textView selectedRange]];
    });
}


//=======================================================
// OgreTextFindResultDelegateProtocol  < result
//=======================================================

// ------------------------------------------------------
/// live update
- (void)didUpdateTextFindResult:(id)textFindResult
// ------------------------------------------------------
{
    if ([self enableLiveUpdate]) {
        [self reloadResult];
    }
}



#pragma mark Private Methods

// ------------------------------------------------------
/// return text view result adding interface for OgreKit private class
- (OgreFindResultBranch<OgreTextViewFindResultInterface> *)textViewResult
// ------------------------------------------------------
{
    return [[[self result] result] childAtIndex:0 inSelection:NO];
}


// ------------------------------------------------------
/// apply actual result to UI
- (void)reloadResult
// ------------------------------------------------------
{
    if (![self result]) { return; }
    
    [self setFindString:[[self result] findString]];
    [self setCount:[[self result] numberOfMatches]];
    [self setDocumentName:[[self result] title]];
    
    NSString *message;
    if ([self count] == 0) {
        message = [NSString stringWithFormat:NSLocalizedString(@"No strings found in “%@”.", nil), [self documentName]];
    } else if ([self count] == 1) {
        message = [NSString stringWithFormat:NSLocalizedString(@"Found one string in “%@”.", nil), [self documentName]];
    } else {
        message = [NSString stringWithFormat:NSLocalizedString(@"Found %li strings in “%@”.", nil), [self count], [self documentName]];
    }
    [self setResultMessage:message];
    
    [[self tableView] reloadData];
}

@end
