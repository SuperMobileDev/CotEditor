/*
 
 CEKeyBindingsPaneController.m
 
 CotEditor
 http://coteditor.com
 
 Created by 1024jp on 2014-04-18.

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

#import "CEKeyBindingsPaneController.h"
#import "CEKeyBindingsViewController.h"


@interface CEKeyBindingsPaneController ()

@property (nonatomic, nullable) CEKeyBindingsViewController *menuViewController;
@property (nonatomic, nullable) CEKeyBindingsViewController *textViewController;

@property (nonatomic, nullable) IBOutlet NSTabView *tabView;

@end


@implementation CEKeyBindingsPaneController

#pragma mark Action Messages

// ------------------------------------------------------
/// open key bindng edit sheet
- (void)viewDidLoad
// ------------------------------------------------------
{
    [self setMenuViewController:[[CEKeyBindingsViewController alloc] initWithMode:CEMenuKeyBindingsType]];
    [self setTextViewController:[[CEKeyBindingsViewController alloc] initWithMode:CETextKeyBindingsType]];
    
    [[[self tabView] tabViewItemAtIndex:0] setView:[[self menuViewController] view]];
    [[[self tabView] tabViewItemAtIndex:1] setView:[[self textViewController] view]];
}

@end
