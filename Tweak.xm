#import <Carousel.h>
#import <Comment.h>
#import <Post.h>
#import <ToggleImageTableViewCell.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import "Preferences.h"
#import "DebugMenu.h"

// --- Cache Setup ---
static NSCache *imageCache;
static NSCache *stringCache;
static NSSet<NSString *> *ignoredOperationsSet;

typedef struct {
    BOOL promoted;
    BOOL recommended;
    BOOL nsfw;
    BOOL awards;
    BOOL scores;
    BOOL automod;
} RedditFilterPrefs;

// Optimization 1: Global preferences struct managed via Darwin Notifications
static RedditFilterPrefs globalPrefs;

static void loadPreferences() {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    globalPrefs.promoted = [defaults objectForKey:kRedditFilterPromoted] ? [defaults boolForKey:kRedditFilterPromoted] : YES;
    globalPrefs.recommended = [defaults boolForKey:kRedditFilterRecommended];
    globalPrefs.nsfw = [defaults boolForKey:kRedditFilterNSFW];
    globalPrefs.awards = [defaults boolForKey:kRedditFilterAwards];
    globalPrefs.scores = [defaults boolForKey:kRedditFilterScores];
    globalPrefs.automod = [defaults boolForKey:kRedditFilterAutoCollapseAutoMod];
}

static void prefsNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
}

@interface CUICatalog : NSObject {
  NSBundle *_bundle;
}
- (NSArray<NSString *> *)allImageNames;
- (instancetype)initWithName:(NSString *)name fromBundle:(NSBundle *)bundle;
- (instancetype)initWithName:(NSString *)name fromBundle:(NSBundle *)bundle error:(NSError **)error;
@end

static NSMutableArray<NSBundle *> *assetBundles;
static NSMutableArray<CUICatalog *> *assetCatalogs;

extern "C" UIImage *iconWithName(NSString *iconName) {
    if (!iconName) return nil;
    
    // Check Cache First
    UIImage *cachedImage = [imageCache objectForKey:iconName];
    if (cachedImage) return cachedImage;

    // Optimization 3: Try public UIKit API first to mitigate private API fragility
    for (NSBundle *bundle in assetBundles) {
        UIImage *image = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:nil];
        if (image) {
            [imageCache setObject:image forKey:iconName];
            return image;
        }
    }

    // Fallback to internal CUICatalog properties if standard retrieval fails
    for (CUICatalog *catalog in assetCatalogs) {
        for (NSString *imageName in [catalog allImageNames]) {
            if ([imageName hasPrefix:iconName] &&
                (imageName.length == iconName.length || imageName.length == iconName.length + 3)) {
                
                // SAFELY retrieve the private _bundle ivar
                Ivar bundleIvar = class_getInstanceVariable(object_getClass(catalog), "_bundle");
                if (!bundleIvar) continue;
                
                NSBundle *bundle = object_getIvar(catalog, bundleIvar);
                if (!bundle) continue;
                
                UIImage *image = [UIImage imageNamed:imageName
                                            inBundle:bundle
                       compatibleWithTraitCollection:nil];
                if (image) {
                    [imageCache setObject:image forKey:iconName];
                    return image;
                }
            }
        }
    }
    return nil;
}

extern "C" NSString *localizedString(NSString *key, NSString *table) {
    if (!key) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%@", key, table ?: @"nil"];
    NSString *cachedString = [stringCache objectForKey:cacheKey];
    if (cachedString) return cachedString;
    
    for (NSBundle *bundle in assetBundles) {
        NSString *localizedString = [bundle localizedStringForKey:key value:nil table:table];
        if (![localizedString isEqualToString:key]) {
            [stringCache setObject:localizedString forKey:cacheKey];
            return localizedString;
        }
    }
    return nil;
}

extern "C" Class CoreClass(NSString *name) {
  Class cls = NSClassFromString(name);
  NSArray *prefixes = @[
    @"Reddit.",
    @"RedditCore.",
    @"RedditCoreModels.",
    @"RedditCore_RedditCoreModels.",
    @"RedditUI.",
  ];
  for (NSString *prefix in prefixes) {
    if (cls) break;
    cls = NSClassFromString([prefix stringByAppendingString:name]);
  }
  return cls;
}

static BOOL shouldFilterObject(id object) {
    // Optimization 1: Use globally cached preferences
    BOOL filterPromoted = globalPrefs.promoted;
    BOOL filterRecommended = globalPrefs.recommended;
    BOOL filterNSFW = globalPrefs.nsfw;

    // If no relevant filters are on, return early
    if (!filterPromoted && !filterRecommended && !filterNSFW) return NO;

    // Do introspection
    NSString *className = NSStringFromClass(object_getClass(object));

    // 1. Check Promoted (Ads)
    if (filterPromoted) {
        BOOL isAdPost = [className hasSuffix:@"AdPost"] ||
                        ([object respondsToSelector:@selector(isAdPost)] && ((Post *)object).isAdPost) ||
                        ([object respondsToSelector:@selector(isPromotedUserPostAd)] && [(Post *)object isPromotedUserPostAd]) ||
                        ([object respondsToSelector:@selector(isPromotedCommunityPostAd)] && [(Post *)object isPromotedCommunityPostAd]);
        if (isAdPost) return YES;
    }

    // 2. Check Recommended
    if (filterRecommended) {
        BOOL isRecommendation = [className containsString:@"Recommend"];
        if (isRecommendation) return YES;
    }

    // 3. Check NSFW
    if (filterNSFW) {
        BOOL isNSFW = [object respondsToSelector:@selector(isNSFW)] && ((Post *)object).isNSFW;
        if (isNSFW) return YES;
    }

    return NO;
}

static NSArray *filteredObjects(NSArray *objects) {
  return [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                                               id object, NSDictionary *bindings) {
        return !shouldFilterObject(object);
  }]];
}

static void filterNode(NSMutableDictionary *node, RedditFilterPrefs prefs) {
    if (![node isKindOfClass:NSMutableDictionary.class]) return;
    
    // Fetch typeName once and ensure it is a valid string to prevent unrecognized selector crashes
    NSString *typeName = node[@"__typename"];
    if (![typeName isKindOfClass:NSString.class]) return;

    if ([typeName isEqualToString:@"SubredditPost"]) {
        if (prefs.awards) {
            node[@"awardings"] = @[];
            node[@"isGildable"] = @NO;
        }
        if (prefs.scores) node[@"isScoreHidden"] = @YES;
        if (prefs.nsfw && [node[@"isNsfw"] boolValue]) node[@"isHidden"] = @YES;
    } 
    else if ([typeName isEqualToString:@"Comment"]) {
        if (prefs.awards) {
            node[@"awardings"] = @[];
            node[@"isGildable"] = @NO;
        }
        if (prefs.scores) node[@"isScoreHidden"] = @YES;
        if (prefs.automod) {
		  NSDictionary *authorInfo = node[@"authorInfo"];
		  if ([authorInfo isKindOfClass:NSDictionary.class]) {
			id authorId = authorInfo[@"id"];
			if ([authorId isKindOfClass:NSString.class] &&
				[authorId isEqualToString:@"t2_6l4z3"]) {
			  node[@"isInitiallyCollapsed"] = @YES;
			}
		  }
		}
    }
    else if ([typeName isEqualToString:@"CellGroup"]) {
        // 1. Check Promoted (AdPayloads)
        if (prefs.promoted && [node[@"adPayload"] isKindOfClass:NSDictionary.class]) {
            node[@"cells"] = @[];
            return; // Exit early if we cleared the cells
        }

        // 2. Check Recommended
		if (prefs.recommended && [node[@"recommendationContext"] isKindOfClass:NSDictionary.class]) {
			NSDictionary *recContext = node[@"recommendationContext"];
			id recTypeName = recContext[@"typeName"];
			id typeIdentifier = recContext[@"typeIdentifier"];

			if ([recTypeName isKindOfClass:NSString.class] && 
				[typeIdentifier isKindOfClass:NSString.class]) {
				
				// Check if the post is part of the standard Popular feed
				BOOL isPopularFeed = [recTypeName isEqualToString:@"PopularRecommendationContext"] || 
									 [typeIdentifier hasPrefix:@"global_popular"];
				
				// If it's NOT the popular feed, it is a home-feed recommendation. Wipe it.
				if (!isPopularFeed) {
					node[@"cells"] = @[];
					return; 
				}
			}
		}

        // 3. Process remaining ActionCells ONLY if Awards or Scores filters are enabled
        if (prefs.awards || prefs.scores) {
            NSMutableArray *cells = node[@"cells"];
            if ([cells isKindOfClass:NSMutableArray.class]) {
                for (NSMutableDictionary *cell in cells) {
                    if (![cell isKindOfClass:NSMutableDictionary.class]) continue;
                    if ([cell[@"__typename"] isEqualToString:@"ActionCell"]) {
                        if (prefs.awards) {
                            cell[@"isAwardHidden"] = @YES;
                            id goldenInfo = cell[@"goldenUpvoteInfo"];
                            if ([goldenInfo isKindOfClass:NSMutableDictionary.class]) {
                                ((NSMutableDictionary *)goldenInfo)[@"isGildable"] = @NO;
                            }
                        }
                        if (prefs.scores) cell[@"isScoreHidden"] = @YES;
                    }
                }
            }
        }
    }
    else if ([typeName isEqualToString:@"AdPost"]) {
        if (prefs.promoted) node[@"isHidden"] = @YES;
    }
}

// Generic, schema-agnostic filtering. Used for unknown operations and, now,
// as the fallback whenever a known operation's hardcoded fast path fails to
// resolve (e.g. after Reddit renames part of its GraphQL schema).
static void filterGenericResponse(NSMutableDictionary *json, RedditFilterPrefs prefs) {
  if (![json[@"data"] isKindOfClass:NSDictionary.class]) return;

  NSDictionary *dataDict = json[@"data"];
  id root = dataDict.allValues.firstObject;
  
  if ([root isKindOfClass:NSDictionary.class]) {
    NSMutableDictionary *rootDict = (NSMutableDictionary *)root;
    
    // Read the first child once instead of re-evaluating allValues repeatedly
    id firstChild = rootDict.allValues.firstObject;
    
    if ([firstChild isKindOfClass:NSDictionary.class]) {
      id edges = ((NSDictionary *)firstChild)[@"edges"];
      if ([edges isKindOfClass:NSArray.class]) {
        for (NSMutableDictionary *edge in (NSArray *)edges)
          if ([edge isKindOfClass:NSDictionary.class])
            filterNode(edge[@"node"], prefs);
      }
    }

    id commentForest = rootDict[@"commentForest"];
    if ([commentForest isKindOfClass:NSDictionary.class]) {
      id trees = ((NSDictionary *)commentForest)[@"trees"];
      if ([trees isKindOfClass:NSArray.class]) {
        for (NSMutableDictionary *tree in (NSArray *)trees)
          if ([tree isKindOfClass:NSDictionary.class])
            filterNode(tree[@"node"], prefs);
      }
    }

    // Optimization 1 & 4: Reuse passed preferences
    if (prefs.promoted && rootDict[@"commentsPageAds"])
      rootDict[@"commentsPageAds"] = @[];
    
    if (prefs.promoted && rootDict[@"commentTreeAds"])
      rootDict[@"commentTreeAds"] = @[];
      
    if (prefs.promoted && rootDict[@"pdpCommentsAds"]) // Kept just in case the fast path misses
      rootDict[@"pdpCommentsAds"] = @[];
      
    if (rootDict[@"recommendations"] && prefs.recommended)
      rootDict[@"recommendations"] = @[];
      
  } else if ([root isKindOfClass:NSArray.class]) {
    for (NSMutableDictionary *node in (NSArray *)root)
      filterNode(node, prefs);
  }
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response,
                                                        NSError *error))completionHandler {
  if (![request.URL.host hasPrefix:@"gql"] && 
      ![request.URL.host hasPrefix:@"oauth"])
    return %orig;

  // Prevent crashes if the underlying method passed a nil completion handler
  if (!completionHandler) {
      return %orig;
  }

  void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) =
      ^(NSData *data, NSURLResponse *response, NSError *error) {
        // Safe bail-out to avoid executing NSJSONSerialization on empty/broken payloads
        if (error || !data || data.length == 0) return completionHandler(data, response, error);

        // Identify the GraphQL Operation Safely (Optimization 2)
        NSString *operationName = @"Unknown";
        
        if (request.HTTPBody) {
            NSString *bodyString = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            if (bodyString) {
                // Avoid NSJSONSerialization, extract operationName directly using regex
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\"(?:operationName|id)\"\\s*:\\s*\"([^\"]+)\"" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:bodyString options:0 range:NSMakeRange(0, bodyString.length)];
                if (match && match.numberOfRanges > 1) {
                    operationName = [bodyString substringWithRange:[match rangeAtIndex:1]];
                }
            }
        } else if ([request.URL.query containsString:@"operationName="]) {
            NSArray *components = [request.URL.query componentsSeparatedByString:@"&"];
            for (NSString *param in components) {
                if ([param hasPrefix:@"operationName="]) {
                    operationName = [param substringFromIndex:14];
                    break;
                }
            }
        }

        // Ignore Telemetry & Configs (Performance Saver - Placed BEFORE response deserialization!)
        if ([ignoredOperationsSet containsObject:operationName]) {
            return completionHandler(data, response, error);
        }

        NSError *jsonError = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:data
                                                        options:NSJSONReadingMutableContainers
                                                          error:&jsonError];
                                                          
        if (jsonError || !jsonObject || ![jsonObject isKindOfClass:NSDictionary.class]) {
            return completionHandler(data, response, error);
        }

        NSMutableDictionary *json = (NSMutableDictionary *)jsonObject;
        
        // Optimization 1: Use globally cached preferences
        RedditFilterPrefs prefs = globalPrefs;

        // Fast path based on known schemas.
        if ([operationName isEqualToString:@"HomeFeedSdui"]) {
            id edges = [json valueForKeyPath:@"data.homeV3.elements.edges"];
            BOOL resolved = [edges isKindOfClass:NSArray.class];
            RF_RECORD_SCHEMA(@"HomeFeedSdui", @"data.homeV3.elements.edges", resolved, json, RFSchemaSigEdges);
            
            if (resolved) {
                for (NSMutableDictionary *edge in (NSArray *)edges)
                    filterNode(edge[@"node"], prefs);
            } else {
                filterGenericResponse(json, prefs);
            }
        } else if ([operationName isEqualToString:@"PopularFeedSdui"]) {
            id edges = [json valueForKeyPath:@"data.popularV3.elements.edges"];
            BOOL resolved = [edges isKindOfClass:NSArray.class];
            RF_RECORD_SCHEMA(@"PopularFeedSdui", @"data.popularV3.elements.edges", resolved, json, RFSchemaSigEdges);
            
            if (resolved) {
                for (NSMutableDictionary *edge in (NSArray *)edges)
                    filterNode(edge[@"node"], prefs);
            } else {
                filterGenericResponse(json, prefs);
            }
        } else if ([operationName isEqualToString:@"FeedPostDetailsByIds"]) {
            id nodes = [json valueForKeyPath:@"data.postsInfoByIds"];
            BOOL resolved = [nodes isKindOfClass:NSArray.class];
            RF_RECORD_SCHEMA(@"FeedPostDetailsByIds", @"data.postsInfoByIds", resolved, json, RFSchemaSigNodeArray);
            
            if (resolved) {
                for (NSMutableDictionary *node in (NSArray *)nodes)
                    filterNode(node, prefs);
            } else {
                filterGenericResponse(json, prefs);
            }
        } else if ([operationName isEqualToString:@"PostInfoByIdComments"] || [operationName isEqualToString:@"PostInfoById"]) {
            NSMutableDictionary *postInfo = [json valueForKeyPath:@"data.postInfoById"];
            id trees = [postInfo valueForKeyPath:@"commentForest.trees"];
            // It's a "hit" if we found the trees array, OR if the post loaded perfectly but simply has 0 comments (commentForest is entirely omitted).
            BOOL resolved = [trees isKindOfClass:NSArray.class] || 
                            ([postInfo isKindOfClass:NSDictionary.class] && postInfo[@"commentForest"] == nil);             
            RF_RECORD_SCHEMA(@"PostInfoById", @"data.postInfoById.commentForest.trees", resolved, json, RFSchemaSigTrees);
            
            if (resolved) {
                if ([trees isKindOfClass:NSArray.class]) {
                    for (NSMutableDictionary *tree in (NSArray *)trees)
                        filterNode(tree[@"node"], prefs);
                }
            } else {
                filterGenericResponse(json, prefs);
            }
            if ([postInfo isKindOfClass:NSDictionary.class]) {
                filterNode(postInfo, prefs);
            }
        } else if ([operationName isEqualToString:@"PdpCommentsAds"]) {
            // Locate the comment-ads container, then clear it if Promoted filtering is on.
            NSMutableDictionary *adContainer = nil;
            if ([json[@"data"] isKindOfClass:NSDictionary.class]) {
                NSMutableDictionary *dataDict = json[@"data"];
                id container = dataDict.allValues.firstObject;
                if ([container isKindOfClass:NSMutableDictionary.class] &&
                    ((NSMutableDictionary *)container)[@"pdpCommentsAds"]) {
                    adContainer = (NSMutableDictionary *)container;
                }
            }
            BOOL resolved = (adContainer != nil);
            RF_RECORD_SCHEMA(@"PdpCommentsAds", @"data.*.pdpCommentsAds", resolved, json, RFSchemaSigCommentsAds);
            
            if (prefs.promoted) {
                if (resolved) {
                    adContainer[@"pdpCommentsAds"] = @[];
                } else {
                    filterGenericResponse(json, prefs);
                }
            }
        } else {
            // Unknown operation (e.g. ProfileFeedSdui): use the generic filter.
            filterGenericResponse(json, prefs);
        }

        NSData *modifiedData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        completionHandler(modifiedData ?: data, response, error);
      };
  return %orig(request, newCompletionHandler);
}
%end

// Only necessary for older app versions
%group Legacy

%hook Listing
- (void)fetchNextPage:(id (^)(NSArray *, id))completionHandler {
  id (^newCompletionHandler)(NSArray *, id) = ^(NSArray *objects, id _) {
    return completionHandler(filteredObjects(objects), _);
  };
  return %orig(newCompletionHandler);
}
%end

%hook FeedNetworkSource
- (NSArray *)postsAndCommentsFromData:(id)data {
  NSArray *origArray = %orig;
  return filteredObjects(origArray);
}
%end

%hook PostDetailPresenter
- (BOOL)shouldFetchCommentAdPost {
  return globalPrefs.promoted ? NO : %orig;
}
- (BOOL)shouldFetchAdditionalCommentAdPosts {
  return globalPrefs.promoted ? NO : %orig;
}
%end

%hook Carousel
- (BOOL)isHiddenByUserWithAccountSettings:(id)accountSettings {
  return (globalPrefs.recommended &&
          ([self.analyticType containsString:@"recommended"] ||
           [self.analyticType containsString:@"similar"] ||
           [self.analyticType containsString:@"popular"])) ||
         %orig;
}
%end

%hook QuickActionViewModel
- (void)fetchActions {
  if (globalPrefs.recommended) return;
  %orig;
}
%end

%hook Post
- (NSArray *)awardingTotals {
  return globalPrefs.awards ? nil : %orig;
}
- (NSUInteger)totalAwardsReceived {
  return globalPrefs.awards ? 0 : %orig;
}
- (BOOL)canAward {
  return globalPrefs.awards ? NO : %orig;
}
- (BOOL)isScoreHidden {
  return globalPrefs.scores ? YES : %orig;
}
%end

%hook Comment
- (NSArray *)awardingTotals {
  return globalPrefs.awards ? nil : %orig;
}
- (NSUInteger)totalAwardsReceived {
  return globalPrefs.awards ? 0 : %orig;
}
- (BOOL)canAward {
  return globalPrefs.awards ? NO : %orig;
}
- (BOOL)shouldHighlightForHighAward {
  return globalPrefs.awards ? NO : %orig;
}
- (BOOL)isScoreHidden {
  return globalPrefs.scores ? YES : %orig;
}
- (BOOL)shouldAutoCollapse {
  return globalPrefs.automod &&
                 [((Comment *)self).authorPk isEqualToString:@"t2_6l4z3"]
             ? YES
             : %orig;
}
%end

// Create a static key for associated objects
static char kConstraintsAddedKey;

%hook ToggleImageTableViewCell
- (void)updateConstraints {
    %orig;
    // Prevent adding duplicate constraints if updateConstraints is called multiple times.
    NSNumber *constraintsAdded = objc_getAssociatedObject(self, &kConstraintsAddedKey);
    if (constraintsAdded.boolValue) return;
    
    UIStackView *horizontalStackView = [self respondsToSelector:@selector(imageLabelView)]
          ? [self imageLabelView].horizontalStackView
          : object_getIvar(self, class_getInstanceVariable(object_getClass(self), "horizontalStackView"));
          
    UILabel *detailLabel = [self respondsToSelector:@selector(imageLabelView)]
                             ? [self imageLabelView].detailLabel
                             : [self detailLabel];
                             
    if (!horizontalStackView || !detailLabel) return;
  
    if (detailLabel.text) {
        UIView *contentView = [self contentView];
        [contentView addConstraints:@[
            [NSLayoutConstraint constraintWithItem:detailLabel
                                         attribute:NSLayoutAttributeHeight
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:horizontalStackView
                                         attribute:NSLayoutAttributeHeight
                                        multiplier:.33
                                          constant:0],
            [NSLayoutConstraint constraintWithItem:horizontalStackView
                                         attribute:NSLayoutAttributeHeight
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:contentView
                                         attribute:NSLayoutAttributeHeight
                                        multiplier:1
                                          constant:0],
            [NSLayoutConstraint constraintWithItem:horizontalStackView
                                         attribute:NSLayoutAttributeCenterY
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:contentView
                                         attribute:NSLayoutAttributeCenterY
                                        multiplier:1
                                          constant:0]
        ]];
        // Mark as added
        objc_setAssociatedObject(self, &kConstraintsAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
%end

%end

%ctor {
  // Initialize caches
  imageCache = [[NSCache alloc] init];
  stringCache = [[NSCache alloc] init];
  
  // Initialize Ignored Operations Set
  ignoredOperationsSet = [[NSSet alloc] initWithObjects:
      @"GetAccount", @"FetchIdentityPreferences", @"DynamicConfigsByNames",
      @"GetAllExperimentVariants", @"AdsOffRedditLocation", @"UserLocation",
      @"CookiePreferences", @"FetchSubscribedSubreddits", @"AdsOffRedditPreferences",
      @"Age", @"RecommendedPrompts", @"EnrollInGamification", @"BadgeCounts",
      @"GetEligibleUXExperiences", @"GetUserAdEligibility", @"GoldBalances",
      @"PaymentSubscriptions", @"FeaturedDevvitGame", @"ModQueueNewItemCount",
      @"LastModeratedSubredditName", @"AwardProductOffers", @"BlockedRedditors",
      @"GamesPreferences", @"GetRedditUsersByIds", @"SubredditsForNames",
      @"SubredditsForIds", @"ExposeExperimentBatch", @"GetProfilePostFlairTemplates",
      @"GetRedditorByNameApollo", @"GetActiveSubreddits", @"GetMyShowcaseCarousel",
      @"UserPublicTrophies", @"PostDraftsCount", @"BrandToolsStatus",
      @"NotificationInbox", @"TrendingSearchesQuery", nil];

  assetBundles = [NSMutableArray array];
  assetCatalogs = [NSMutableArray array];
  [assetBundles addObject:NSBundle.mainBundle];
  
  for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSBundle.mainBundle.bundlePath error:nil]) {
    if (![file hasSuffix:@"bundle"]) continue;
    NSBundle *bundle = [NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:[file stringByDeletingPathExtension] ofType:@"bundle"]];
    if (bundle) [assetBundles addObject:bundle];
  }
  
  for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"] error:nil]) {
    if (![file hasSuffix:@"framework"]) continue;
    NSString *frameworkPath = [NSBundle.mainBundle pathForResource:[file stringByDeletingPathExtension] ofType:@"framework" inDirectory:@"Frameworks"];
    NSBundle *bundle = [NSBundle bundleWithPath:frameworkPath];
    if (bundle) [assetBundles addObject:bundle];
    
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:frameworkPath error:nil]) {
      if (![file hasSuffix:@"bundle"]) continue;
      NSBundle *bundle = [NSBundle bundleWithPath:[frameworkPath stringByAppendingPathComponent:file]];
      if (bundle) [assetBundles addObject:bundle];
    }
  }
  
  for (NSBundle *bundle in assetBundles) {
    NSError *error;
    CUICatalog *catalog = [[%c(CUICatalog) alloc] initWithName:@"Assets" fromBundle:bundle error:&error];
    if (!error) [assetCatalogs addObject:catalog];
  }
  
  // Correct keys used for default values.
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  
  if (![defaults objectForKey:kRedditFilterPromoted])
    [defaults setBool:true forKey:kRedditFilterPromoted];
  if (![defaults objectForKey:kRedditFilterRecommended])
    [defaults setBool:false forKey:kRedditFilterRecommended];
  if (![defaults objectForKey:kRedditFilterNSFW])
    [defaults setBool:false forKey:kRedditFilterNSFW];
  if (![defaults objectForKey:kRedditFilterAwards])
    [defaults setBool:false forKey:kRedditFilterAwards];
  if (![defaults objectForKey:kRedditFilterScores])
    [defaults setBool:false forKey:kRedditFilterScores];
  if (![defaults objectForKey:kRedditFilterAutoCollapseAutoMod])
    [defaults setBool:false forKey:kRedditFilterAutoCollapseAutoMod];

  // Set up cached struct & notification listener
  loadPreferences();
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, prefsNotificationCallback, CFSTR("com.level3tjg.redditfilter/prefsUpdated"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    
  %init;
  %init(Legacy, Comment = CoreClass(@"Comment"), Post = CoreClass(@"Post"),
                   QuickActionViewModel = CoreClass(@"QuickActionViewModel"),
                   ToggleImageTableViewCell = CoreClass(@"ToggleImageTableViewCell"));
}
