#import "FeedFilterSettingsViewController.h"
#import "DebugMenu.h"
#import <CoreFoundation/CoreFoundation.h>

extern NSString *localizedString(NSString *key, NSString *table);
extern UIImage *iconWithName(NSString *iconName);
extern Class CoreClass(NSString *name);

#define LOC(x, d) (localizedString(x, nil) ?: d)

// Helper to notify Tweak.xm that preferences have changed
static void NotifyPreferencesChanged() {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
                                         CFSTR("com.redditfilter.prefs-updated"), 
                                         NULL, 
                                         NULL, 
                                         true);
}

#if REDDITFILTER_DEBUG
@interface FeedFilterSettingsViewController (RFSchemaDebug)
- (UITableViewCell *)debugCellForRow:(NSInteger)row inTableView:(UITableView *)tableView;
- (void)rfCopyDiscoveredPath:(UIButton *)sender;
- (void)rfCopyFailedJSON:(UIButton *)sender;
- (void)rfResetCounters:(UIButton *)sender;
@end
#endif

%subclass FeedFilterSettingsViewController : BaseTableViewController
%new
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
#if REDDITFILTER_DEBUG
  return 2;
#else
  return 1;
#endif
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case 0:
      return 6;
#if REDDITFILTER_DEBUG
    case 1:
      return [[RFSchemaDebug shared] snapshot].count + 1;
#endif
    default:
      return 0;
  }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *mainLabelText;
  NSString *detailLabelText;
  NSArray *iconNames;
  ToggleImageTableViewCell *toggleCell;
  ImageLabelTableViewCell *cell;
  
  switch (indexPath.section) {
    case 0: {
      toggleCell = [tableView dequeueReusableCellWithIdentifier:kToggleCellID forIndexPath:indexPath];
      
      // Fix: Prevent switch handler accumulation on cell reuse
      [toggleCell.accessorySwitch removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
      
      switch (indexPath.row) {
        case 0:
          mainLabelText = LOC(@"filter.settings.promoted.title", @"Promoted");
          iconNames = @[ @"rpl3/tag", @"icon_tag" ];
          toggleCell.accessorySwitch.on = ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterPromoted];
          [toggleCell.accessorySwitch addTarget:self action:@selector(didTogglePromotedSwitch:) forControlEvents:UIControlEventValueChanged];
          break;
        case 1:
          mainLabelText = LOC(@"filter.settings.recommended.title", @"Recommended");
          iconNames = @[ @"rpl3/spam", @"icon_spam" ];
          toggleCell.accessorySwitch.on = ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterRecommended];
          [toggleCell.accessorySwitch addTarget:self action:@selector(didToggleRecommendedSwitch:) forControlEvents:UIControlEventValueChanged];
          break;
        case 2:
          mainLabelText = LOC(@"filter.settings.nsfw.title", @"NSFW");
          iconNames = @[ @"rpl3/nsfw", @"icon_nsfw_outline", @"icon_nsfw" ];
          toggleCell.accessorySwitch.on = ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterNSFW];
          [toggleCell.accessorySwitch addTarget:self action:@selector(didToggleNsfwSwitch:) forControlEvents:UIControlEventValueChanged];
          break;
        case 3:
          mainLabelText = LOC(@"filter.settings.awards.title", @"Awards");
          detailLabelText = LOC(@"filter.settings.awards.subtitle", @"Show awards on posts and comments");
          iconNames = @[ @"rpl3/award",  @"icon_gift_fill", @"icon_award", @"icon-award-outline" ];
          toggleCell.accessorySwitch.on = ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterAwards];
          [toggleCell.accessorySwitch addTarget:self action:@selector(didToggleAwardsSwitch:) forControlEvents:UIControlEventValueChanged];
          break;
        case 4:
          mainLabelText = LOC(@"filter.settings.scores.title", @"Scores");
          detailLabelText = LOC(@"filter.settings.scores.subtitle", @"Show vote count on posts and comments");
          iconNames = @[ @"rpl3/upvote", @"icon_upvote" ];
          toggleCell.accessorySwitch.on = ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterScores];
          [toggleCell.accessorySwitch addTarget:self action:@selector(didToggleScoresSwitch:) forControlEvents:UIControlEventValueChanged];
          break;
        case 5:
          mainLabelText = LOC(@"filter.settings.automod.title", @"AutoMod");
          detailLabelText = LOC(@"filter.settings.automod.subtitle", @"Auto collapse AutoMod comments");
          iconNames = @[ @"rpl3/mod", @"icon_mod" ];
          toggleCell.accessorySwitch.on = [NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterAutoCollapseAutoMod];
          [toggleCell.accessorySwitch addTarget:self action:@selector(didToggleAutoCollapseAutoModSwitch:) forControlEvents:UIControlEventValueChanged];
          break;
        default:
          return nil;
      }
      cell = toggleCell;
      break;
    }
#if REDDITFILTER_DEBUG
    case 1:
      return [self debugCellForRow:indexPath.row inTableView:tableView];
#endif
    default:
      return nil;
  }

  ([cell respondsToSelector:@selector(mainLabel)] ? cell.mainLabel : cell.imageLabelView.mainLabel).text = mainLabelText;
  ([cell respondsToSelector:@selector(detailLabel)] ? cell.detailLabel : cell.imageLabelView.detailLabel).text = detailLabelText;
  
  UIImage *iconImage;
  for (NSString *iconName in iconNames) {
    iconImage = iconWithName(iconName);
    if (iconImage) break;
  }

  if (iconImage) {
    UIImage *displayImage = [[iconImage imageScaledToSize:CGSizeMake(20, 20)] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if ([cell respondsToSelector:@selector(setDisplayImage:)])
      cell.displayImage = displayImage;
    else
      cell.imageLabelView.imageView.image = displayImage;
  }

  return cell;
}

%new
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
  BaseLabel *label = [%c(BaseLabel) labelWithSubheaderFont];
  LayoutGuidance *layoutGuidance = [%c(LayoutGuidance) currentGuidance];
  label.frame = CGRectMake(layoutGuidance.gridPadding, 0, layoutGuidance.maxContentWidth - layoutGuidance.gridPaddingDouble, 40.0);
  [label associatePropertySetter:@selector(setTextColor:) withThemePropertyGetter:@selector(metaTextColor)];
  
  BaseTableReusableView *headerView = [[%c(BaseTableReusableView) alloc] initWithFrame:CGRectMake(0, 0, tableView.frameWidth, 40.0)];
  [headerView.contentView addSubview:label];
  [headerView associatePropertySetter:@selector(setBackgroundColor:) withThemePropertyGetter:@selector(canvasColor)];
  
  switch (section) {
    case 0:
      label.text = [LOC(@"filter.settings.header", @"Filters") uppercaseString];
      break;
#if REDDITFILTER_DEBUG
    case 1:
      label.text = [@"Schema Paths · Debug" uppercaseString];
      break;
#endif
    default:
      return nil;
  }
  return headerView;
}

%new
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
  return 40.0;
}

%new
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
  CGFloat footerHeight = [self tableView:tableView heightForFooterInSection:section];
  BaseLabel *label = [%c(BaseLabel) labelWithSubheaderFont];
  LayoutGuidance *layoutGuidance = [%c(LayoutGuidance) currentGuidance];
  label.frame = CGRectMake(layoutGuidance.gridPadding, 0, layoutGuidance.maxContentWidth - layoutGuidance.gridPaddingDouble, footerHeight);
  [label associatePropertySetter:@selector(setTextColor:) withThemePropertyGetter:@selector(metaTextColor)];
  
  BaseTableReusableView *footerView = [[%c(BaseTableReusableView) alloc] initWithFrame:CGRectMake(0, 0, tableView.frameWidth, footerHeight)];
  [footerView.contentView addSubview:label];
  [footerView associatePropertySetter:@selector(setBackgroundColor:) withThemePropertyGetter:@selector(canvasColor)];
  
  switch (section) {
    case 0:
      label.text = LOC(@"filter.settings.footer", @"Filter specific types of posts from your feed");
      break;
#if REDDITFILTER_DEBUG
    case 1:
      label.numberOfLines = 0;
      label.text = @"✓ resolved · ✗ broke (structural fallback is now filtering). Tap Copy on a ✗ row to grab the auto-discovered replacement path.";
      break;
#endif
    default:
      return nil;
  }
  return footerView;
}

%new
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
#if REDDITFILTER_DEBUG
  if (section == 1) return 76.0;
#endif
  return 40.0;
}

- (void)viewDidLoad {
  %orig;
  self.title = @"RedditFilter";
  
  Class toggleCellClass = CoreClass(@"ToggleImageTableViewCell") ?: [UITableViewCell class];
  Class labelCellClass = CoreClass(@"ImageLabelTableViewCell") ?: [UITableViewCell class];
  
  [self.tableView registerClass:toggleCellClass forCellReuseIdentifier:kToggleCellID];
  [self.tableView registerClass:labelCellClass forCellReuseIdentifier:kLabelCellID];
  
#if REDDITFILTER_DEBUG
  self.tableView.estimatedRowHeight = 60.0;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
#endif
}

%new
- (void)didTogglePromotedSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterPromoted];
  NotifyPreferencesChanged();
}
%new
- (void)didToggleRecommendedSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterRecommended];
  NotifyPreferencesChanged();
}
%new
- (void)didToggleNsfwSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterNSFW];
  NotifyPreferencesChanged();
}
%new
- (void)didToggleAwardsSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterAwards];
  NotifyPreferencesChanged();
}
%new
- (void)didToggleScoresSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterScores];
  NotifyPreferencesChanged();
}
%new
- (void)didToggleAutoCollapseAutoModSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:kRedditFilterAutoCollapseAutoMod];
  NotifyPreferencesChanged();
}

// ---------------------------------------------------------------------------
// Schema-path debug section. (Unchanged implementation hidden in response for brevity)
// ---------------------------------------------------------------------------
// ... (The entire REDDITFILTER_DEBUG implementation remains exactly as you authored it)
// ...

- (void)viewWillAppear:(BOOL)animated {
  %orig;
#if REDDITFILTER_DEBUG
  [self.tableView reloadData];
#endif
}
%end
