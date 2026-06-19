#import "FeedFilterSettingsViewController.h"
#import "DebugMenu.h"

extern NSBundle *redditFilterBundle;
extern UIImage *iconWithName(NSString *iconName);
extern Class CoreClass(NSString *name);
#define LOC(x, d) [redditFilterBundle localizedStringForKey:x value:d table:nil]

#if REDDITFILTER_DEBUG
// Visible declarations for the debug-only helpers so the direct call site in
// -cellForRowAtIndexPath: and the @selector(...) references are fully typed.
// (The implementations are added to the class at runtime by Logos below.)
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
      // One row per tracked schema path, plus a trailing "reset" row.
      return [[RFSchemaDebug shared] snapshot].count + 1;
#endif
    default:
      return 0;
  }
}
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *mainLabelText;
  NSString *detailLabelText;
  NSArray *iconNames;
  ToggleImageTableViewCell *toggleCell;
  ImageLabelTableViewCell *cell;
  switch (indexPath.section) {
    case 0: {
      toggleCell = [tableView dequeueReusableCellWithIdentifier:kToggleCellID
                                                   forIndexPath:indexPath];
      switch (indexPath.row) {
        case 0:
          mainLabelText = LOC(@"filter.settings.promoted.title", @"Promoted");
          iconNames = @[ @"rpl3/tag", @"icon_tag" ];
          toggleCell.accessorySwitch.on =
              ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterPromoted];
          [toggleCell.accessorySwitch addTarget:self
                                         action:@selector(didTogglePromotedSwitch:)
                               forControlEvents:UIControlEventValueChanged];
          break;
        case 1:
          mainLabelText = LOC(@"filter.settings.recommended.title", @"Recommended");
          iconNames = @[ @"rpl3/spam", @"icon_spam" ];
          toggleCell.accessorySwitch.on =
              ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterRecommended];
          [toggleCell.accessorySwitch addTarget:self
                                         action:@selector(didToggleRecommendedSwitch:)
                               forControlEvents:UIControlEventValueChanged];
          break;
        case 2:
          mainLabelText = LOC(@"filter.settings.nsfw.title", @"NSFW");
          iconNames = @[ @"rpl3/nsfw", @"icon_nsfw_outline", @"icon_nsfw" ];
          toggleCell.accessorySwitch.on =
              ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterNSFW];
          [toggleCell.accessorySwitch addTarget:self
                                         action:@selector(didToggleNsfwSwitch:)
                               forControlEvents:UIControlEventValueChanged];
          break;
        case 3:
          mainLabelText = LOC(@"filter.settings.awards.title", @"Awards");
          detailLabelText =
              LOC(@"filter.settings.awards.subtitle", @"Show awards on posts and comments");
          iconNames = @[ @"rpl3/award",  @"icon_gift_fill", @"icon_award", @"icon-award-outline" ];
          toggleCell.accessorySwitch.on =
              ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterAwards];
          [toggleCell.accessorySwitch addTarget:self
                                         action:@selector(didToggleAwardsSwitch:)
                               forControlEvents:UIControlEventValueChanged];
          break;
        case 4:
          mainLabelText = LOC(@"filter.settings.scores.title", @"Scores");
          detailLabelText =
              LOC(@"filter.settings.scores.subtitle", @"Show vote count on posts and comments");
          iconNames = @[ @"rpl3/upvote", @"icon_upvote" ];
          toggleCell.accessorySwitch.on =
              ![NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterScores];
          [toggleCell.accessorySwitch addTarget:self
                                         action:@selector(didToggleScoresSwitch:)
                               forControlEvents:UIControlEventValueChanged];
          break;
        case 5:
          mainLabelText = LOC(@"filter.settings.automod.title", @"AutoMod");
          detailLabelText =
              LOC(@"filter.settings.automod.subtitle", @"Auto collapse AutoMod comments");
          iconNames = @[ @"rpl3/mod", @"icon_mod" ];
          toggleCell.accessorySwitch.on =
              [NSUserDefaults.standardUserDefaults boolForKey:kRedditFilterAutoCollapseAutoMod];
          [toggleCell.accessorySwitch addTarget:self
                                         action:@selector(didToggleAutoCollapseAutoModSwitch:)
                               forControlEvents:UIControlEventValueChanged];
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

  ([cell respondsToSelector:@selector(mainLabel)] ? cell.mainLabel : cell.imageLabelView.mainLabel)
      .text = mainLabelText;
  ([cell respondsToSelector:@selector(detailLabel)] ? cell.detailLabel
                                                    : cell.imageLabelView.detailLabel)
      .text = detailLabelText;
  UIImage *iconImage;
  for (NSString *iconName in iconNames) {
    iconImage = iconWithName(iconName);
    if (iconImage) break;
  }

  if (iconImage) {
    UIImage *displayImage = [[iconImage imageScaledToSize:CGSizeMake(20, 20)]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
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
  label.frame = CGRectMake(layoutGuidance.gridPadding, 0,
                           layoutGuidance.maxContentWidth - layoutGuidance.gridPaddingDouble, 40.0);
  [label associatePropertySetter:@selector(setTextColor:)
         withThemePropertyGetter:@selector(metaTextColor)];
  BaseTableReusableView *headerView = [[%c(BaseTableReusableView) alloc]
      initWithFrame:CGRectMake(0, 0, tableView.frameWidth, 40.0)];
  [headerView.contentView addSubview:label];
  [headerView associatePropertySetter:@selector(setBackgroundColor:)
              withThemePropertyGetter:@selector(canvasColor)];
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
  label.frame = CGRectMake(layoutGuidance.gridPadding, 0,
                           layoutGuidance.maxContentWidth - layoutGuidance.gridPaddingDouble,
                           footerHeight);
  [label associatePropertySetter:@selector(setTextColor:)
         withThemePropertyGetter:@selector(metaTextColor)];
  BaseTableReusableView *footerView = [[%c(BaseTableReusableView) alloc]
      initWithFrame:CGRectMake(0, 0, tableView.frameWidth, footerHeight)];
  [footerView.contentView addSubview:label];
  [footerView associatePropertySetter:@selector(setBackgroundColor:)
              withThemePropertyGetter:@selector(canvasColor)];
  switch (section) {
    case 0:
      label.text = LOC(@"filter.settings.footer", @"Filter specific types of posts from your feed");
      break;
#if REDDITFILTER_DEBUG
    case 1:
      label.numberOfLines = 0;
      label.text = @"✓ resolved · ✗ broke (structural fallback is now filtering). "
                   @"Tap Copy on a ✗ row to grab the auto-discovered replacement path.";
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
  
  // Provide safe fallbacks to prevent crashes if Reddit removes/renames classes
  Class toggleCellClass = CoreClass(@"ToggleImageTableViewCell") ?: [UITableViewCell class];
  Class labelCellClass = CoreClass(@"ImageLabelTableViewCell") ?: [UITableViewCell class];
  
  [self.tableView registerClass:toggleCellClass
         forCellReuseIdentifier:kToggleCellID];
  [self.tableView registerClass:labelCellClass
         forCellReuseIdentifier:kLabelCellID];
#if REDDITFILTER_DEBUG
  // Debug rows carry multi-line detail text, so let them self-size.
  self.tableView.estimatedRowHeight = 60.0;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
#endif
}
%new
- (void)didTogglePromotedSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterPromoted];
}
%new
- (void)didToggleRecommendedSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterRecommended];
}
%new
- (void)didToggleNsfwSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterNSFW];
}
%new
- (void)didToggleAwardsSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterAwards];
}
%new
- (void)didToggleScoresSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:!sender.on forKey:kRedditFilterScores];
}
%new
- (void)didToggleAutoCollapseAutoModSwitch:(UISwitch *)sender {
  [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:kRedditFilterAutoCollapseAutoMod];
}

// ---------------------------------------------------------------------------
// Schema-path debug section.
//
// All of the method *declarations* below are compiled unconditionally so that
// Logos always registers them on the subclass; only their bodies are gated on
// REDDITFILTER_DEBUG. In a release build the bodies collapse to no-ops, the
// section is never shown (numberOfSections returns 1), and these methods are
// never invoked.
// ---------------------------------------------------------------------------
%new
- (UITableViewCell *)debugCellForRow:(NSInteger)row inTableView:(UITableView *)tableView {
#if REDDITFILTER_DEBUG
  static NSString *const kRFDebugCellID = @"RFSchemaDebugCell";
  // Deliberately a plain UIKit cell, not a Reddit class: the whole point of
  // this screen is to keep working when Reddit's own classes/schema change.
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRFDebugCellID];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                  reuseIdentifier:kRFDebugCellID];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0
                                                            weight:UIFontWeightRegular];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
  }
  cell.accessoryView = nil;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  NSArray<NSDictionary *> *snapshot = [[RFSchemaDebug shared] snapshot];

  // Trailing "reset" row.
  if (row >= (NSInteger)snapshot.count) {
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.textLabel.text = @"Reset counters";
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.text = @"Clear all stats and re-arm path discovery";
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    [resetButton addTarget:self
                    action:@selector(rfResetCounters:)
          forControlEvents:UIControlEventTouchUpInside];
    [resetButton sizeToFit];
    cell.accessoryView = resetButton;
    return cell;
  }

  NSDictionary *record = snapshot[row];
  NSString *op = record[kRFDebugOp];
  NSString *expected = record[kRFDebugExpected];
  NSString *discovered = record[kRFDebugDiscovered];
  NSInteger hits = [record[kRFDebugHits] integerValue];
  NSInteger misses = [record[kRFDebugMisses] integerValue];
  BOOL seen = [record[kRFDebugSeen] boolValue];
  BOOL lastResolved = [record[kRFDebugLastResolved] boolValue];

  cell.textLabel.textColor = [UIColor labelColor];
  cell.textLabel.text = op;

  NSString *detail;
  UIColor *detailColor;
  if (!seen) {
    detail = [NSString stringWithFormat:@"untested\nexpected: %@", expected];
    detailColor = [UIColor secondaryLabelColor];
  } else if (lastResolved) {
    detail = [NSString stringWithFormat:@"\u2713 OK \u00b7 %ld hit%@",
                                        (long)hits, hits == 1 ? @"" : @"s"];
    if (misses > 0)
      detail = [detail stringByAppendingFormat:@"  (recovered after %ld miss%@)",
                                               (long)misses, misses == 1 ? @"" : @"es"];
    detailColor = [UIColor systemGreenColor];
  } else {
    detail = [NSString stringWithFormat:@"\u2717 MISS \u00b7 %ld miss%@ \u00b7 fallback active",
                                        (long)misses, misses == 1 ? @"" : @"es"];
    if (discovered.length) {
      detail = [detail stringByAppendingFormat:@"\n\u2192 %@", discovered];
      UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
      [copyButton setTitle:@"Copy" forState:UIControlStateNormal];
      copyButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
      copyButton.tag = row;
      [copyButton addTarget:self
                     action:@selector(rfCopyDiscoveredPath:)
           forControlEvents:UIControlEventTouchUpInside];
      [copyButton sizeToFit];
      cell.accessoryView = copyButton;
    } else {
      detail = [detail stringByAppendingFormat:@"\ncould not auto-locate a new path\nexpected: %@",
                                               expected];
                                               
      // Show the "Copy JSON" button if we captured a payload
      NSString *failedJSON = record[kRFDebugFailedJSON];
      if (failedJSON.length > 0) {
          detail = [detail stringByAppendingString:@"\n\u2192 raw payload captured"];
          UIButton *copyJsonButton = [UIButton buttonWithType:UIButtonTypeSystem];
          [copyJsonButton setTitle:@"Copy JSON" forState:UIControlStateNormal];
          copyJsonButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
          copyJsonButton.tag = row;
          [copyJsonButton addTarget:self
                             action:@selector(rfCopyFailedJSON:)
                   forControlEvents:UIControlEventTouchUpInside];
          [copyJsonButton sizeToFit];
          cell.accessoryView = copyJsonButton;
      }
    }
    detailColor = [UIColor systemRedColor];
  }
  cell.detailTextLabel.text = detail;
  cell.detailTextLabel.textColor = detailColor;
  return cell;
#else
  return nil;
#endif
}
%new
- (void)rfCopyDiscoveredPath:(UIButton *)sender {
#if REDDITFILTER_DEBUG
  NSArray<NSDictionary *> *snapshot = [[RFSchemaDebug shared] snapshot];
  if (sender.tag < 0 || sender.tag >= (NSInteger)snapshot.count) return;
  NSString *discovered = snapshot[sender.tag][kRFDebugDiscovered];
  if (!discovered.length) return;
  UIPasteboard.generalPasteboard.string = discovered;
  [sender setTitle:@"Copied" forState:UIControlStateNormal];
  [sender sizeToFit];
  __weak UIButton *weakSender = sender;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [weakSender setTitle:@"Copy" forState:UIControlStateNormal];
                   [weakSender sizeToFit];
                 });
#endif
}
%new
- (void)rfCopyFailedJSON:(UIButton *)sender {
#if REDDITFILTER_DEBUG
  NSArray<NSDictionary *> *snapshot = [[RFSchemaDebug shared] snapshot];
  if (sender.tag < 0 || sender.tag >= (NSInteger)snapshot.count) return;
  
  NSString *failedJSON = snapshot[sender.tag][kRFDebugFailedJSON];
  if (!failedJSON.length) return;
  
  UIPasteboard.generalPasteboard.string = failedJSON;
  [sender setTitle:@"Copied" forState:UIControlStateNormal];
  [sender sizeToFit];
  
  __weak UIButton *weakSender = sender;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [weakSender setTitle:@"Copy JSON" forState:UIControlStateNormal];
                   [weakSender sizeToFit];
                 });
#endif
}
%new
- (void)rfResetCounters:(UIButton *)sender {
#if REDDITFILTER_DEBUG
  [[RFSchemaDebug shared] reset];
  [self.tableView reloadData];
#endif
}
- (void)viewWillAppear:(BOOL)animated {
  %orig;
#if REDDITFILTER_DEBUG
  // Stats accrue while the app runs; refresh them each time the screen opens.
  [self.tableView reloadData];
#endif
}
%end
