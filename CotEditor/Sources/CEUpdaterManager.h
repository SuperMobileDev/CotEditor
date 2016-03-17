/*
 
 CEUpdaterManager.h
 
 CotEditor
 http://coteditor.com
 
 Created by 1024jp on 2015-05-01.

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

@import Foundation;


@interface CEUpdaterManager : NSObject

@property (nonatomic, readonly, getter=isPrerelease) BOOL prerelease;

// singleton
+ (nonnull instancetype)sharedManager;


// Public Methods
/// setup Sparkle (Invoke this in `applicationWillFinishLaunching:`.)
- (void)setup;

@end
