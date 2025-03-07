import WMF;

class OnThisDayViewController: ColumnarCollectionViewController, DetailPresentingFromContentGroup {
    fileprivate static let cellReuseIdentifier = "OnThisDayCollectionViewCell"
    fileprivate static let headerReuseIdentifier = "OnThisDayViewControllerHeader"
    fileprivate static let blankHeaderReuseIdentifier = "OnThisDayViewControllerBlankHeader"

    let events: [WMFFeedOnThisDayEvent]
    let dataStore: MWKDataStore
    let midnightUTCDate: Date
    var initialEvent: WMFFeedOnThisDayEvent?
    let feedFunnelContext: FeedFunnelContext
    let contentGroupIDURIString: String?

    required public init(events: [WMFFeedOnThisDayEvent], dataStore: MWKDataStore, midnightUTCDate: Date, contentGroup: WMFContentGroup, theme: Theme) {
        self.events = events
        self.dataStore = dataStore
        self.midnightUTCDate = midnightUTCDate
        self.isDateVisibleInTitle = false
        feedFunnelContext = FeedFunnelContext(contentGroup)
        self.contentGroupIDURIString = contentGroup.objectID.uriRepresentation().absoluteString
        super.init()
        self.theme = theme
        title = CommonStrings.onThisDayTitle
    }
    
    var isDateVisibleInTitle: Bool {
        didSet {
            
            // Work-around for: https://phabricator.wikimedia.org/T169277
            // Presently the event looks to its first article preview when you ask it for the language, so if the event has no previews, no lang!
            let firstEventWithArticlePreviews = events.first(where: {
                guard let previews = $0.articlePreviews, !previews.isEmpty else {
                    return false
                }
                return true
            })
            
            guard isDateVisibleInTitle, let language = firstEventWithArticlePreviews?.language else {
                title = CommonStrings.onThisDayTitle
                return
            }
            title = DateFormatter.wmf_monthNameDayNumberGMTFormatter(for: language).string(from: midnightUTCDate)
        }
    }
    
    override func metrics(with size: CGSize, readableWidth: CGFloat, layoutMargins: UIEdgeInsets) -> ColumnarCollectionViewLayoutMetrics {
        return ColumnarCollectionViewLayoutMetrics.tableViewMetrics(with: size, readableWidth: readableWidth, layoutMargins: layoutMargins)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        layoutManager.register(OnThisDayCollectionViewCell.self, forCellWithReuseIdentifier: OnThisDayViewController.cellReuseIdentifier, addPlaceholder: true)
        layoutManager.register(UINib(nibName: OnThisDayViewController.headerReuseIdentifier, bundle: nil), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: OnThisDayViewController.headerReuseIdentifier, addPlaceholder: false)
        layoutManager.register(OnThisDayViewControllerBlankHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: OnThisDayViewController.blankHeaderReuseIdentifier, addPlaceholder: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scrollToInitialEvent()
    }
    
    func scrollToInitialEvent() {
        guard let event = initialEvent, let eventIndex = events.firstIndex(of: event), events.indices.contains(eventIndex) else {
            return
        }
        let sectionIndex = eventIndex + 1 // index + 1 because section 0 is the header
        collectionView.scrollToItem(at: IndexPath(item: 0, section: sectionIndex), at: sectionIndex < 1 ? .top : .centeredVertically, animated: false)
    }
    
    override func scrollViewInsetsDidChange() {
        super.scrollViewInsetsDidChange()
        scrollToInitialEvent()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initialEvent = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            FeedFunnel.shared.logFeedCardClosed(for: feedFunnelContext, maxViewed: maxViewed)
        }
    }
    
    // MARK: - ColumnarCollectionViewLayoutDelegate
    
    override func collectionView(_ collectionView: UICollectionView, estimatedHeightForHeaderInSection section: Int, forColumnWidth columnWidth: CGFloat) -> ColumnarCollectionViewLayoutHeightEstimate {
        guard section > 0 else {
            return super.collectionView(collectionView, estimatedHeightForHeaderInSection: section, forColumnWidth: columnWidth)
        }
        return ColumnarCollectionViewLayoutHeightEstimate(precalculated: false, height: section == 1 ? 150 : 0)
    }
    
    override func collectionView(_ collectionView: UICollectionView, estimatedHeightForItemAt indexPath: IndexPath, forColumnWidth columnWidth: CGFloat) -> ColumnarCollectionViewLayoutHeightEstimate {
        var estimate = ColumnarCollectionViewLayoutHeightEstimate(precalculated: false, height: 350)
        guard let placeholderCell = layoutManager.placeholder(forCellWithReuseIdentifier: OnThisDayViewController.cellReuseIdentifier) as? OnThisDayCollectionViewCell else {
            return estimate
        }
        guard let event = event(for: indexPath.section) else {
            return estimate
        }
        placeholderCell.layoutMargins = layout.itemLayoutMargins
        placeholderCell.configure(with: event, dataStore: dataStore, theme: theme, layoutOnly: true, shouldAnimateDots: false)
        estimate.height = placeholderCell.sizeThatFits(CGSize(width: columnWidth, height: UIView.noIntrinsicMetric), apply: false).height
        estimate.precalculated = true
        return estimate
    }

    // MARK: - UIViewControllerPreviewingDelegate

    var previewedIndex: Int?

    override func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = collectionViewIndexPathForPreviewingContext(previewingContext, location: location),
            let cell = collectionView.cellForItem(at: indexPath) as? OnThisDayCollectionViewCell else {
                return nil
        }

        let pointInCellCoordinates =  view.convert(location, to: cell)
        let index = cell.subItemIndex(at: pointInCellCoordinates)
        guard index != NSNotFound, let subItemView = cell.viewForSubItem(at: index) else {
            return nil
        }

        previewedIndex = index

        guard let event = event(for: indexPath.section), let previews = event.articlePreviews, index < previews.count else {
            return nil
        }

        previewingContext.sourceRect = view.convert(subItemView.bounds, from: subItemView)
        let article = previews[index]
        let vc = WMFArticleViewController(articleURL: article.articleURL, dataStore: dataStore, theme: theme)
        vc.articlePreviewingActionsDelegate = self
        vc.wmf_addPeekableChildViewController(for: article.articleURL, dataStore: dataStore, theme: theme)
        if let themeable = vc as Themeable? {
            themeable.apply(theme: self.theme)
        }
        FeedFunnel.shared.logArticleInFeedDetailPreviewed(for: feedFunnelContext, index: index)
        return vc
    }

    override func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        viewControllerToCommit.wmf_removePeekableChildViewControllers()
        FeedFunnel.shared.logArticleInFeedDetailReadingStarted(for: feedFunnelContext, index: previewedIndex, maxViewed: maxViewed)
        wmf_push(viewControllerToCommit, animated: true)
    }

    // MARK: - CollectionViewFooterDelegate

    override func collectionViewFooterButtonWasPressed(_ collectionViewFooter: CollectionViewFooter) {
        navigationController?.popViewController(animated: true)
    }

}

class OnThisDayViewControllerBlankHeader: UICollectionReusableView {

}

// MARK: - UICollectionViewDataSource/Delegate
extension OnThisDayViewController {
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return events.count + 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section > 0 ? 1 : 0
    }
    
    func event(for section: Int) -> WMFFeedOnThisDayEvent? {
        guard section > 0 else {
            return nil
        }
        return events[section - 1]
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OnThisDayViewController.cellReuseIdentifier, for: indexPath)
        guard let onThisDayCell = cell as? OnThisDayCollectionViewCell else {
            return cell
        }
        guard let event = event(for: indexPath.section) else {
            return cell
        }
        onThisDayCell.layoutMargins = layout.itemLayoutMargins
        onThisDayCell.configure(with: event, dataStore: dataStore, theme: self.theme, layoutOnly: false, shouldAnimateDots: true)
        onThisDayCell.timelineView.extendTimelineAboveDot = indexPath.section == 0 ? false : true

        return onThisDayCell
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard indexPath.section > 0, kind == UICollectionView.elementKindSectionHeader else {
            return super.collectionView(collectionView, viewForSupplementaryElementOfKind: kind, at: indexPath)
        }
        guard
            indexPath.section == 1,
            kind == UICollectionView.elementKindSectionHeader,
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: OnThisDayViewController.headerReuseIdentifier, for: indexPath) as? OnThisDayViewControllerHeader
        else {
            return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: OnThisDayViewController.blankHeaderReuseIdentifier, for: indexPath)
        }
        
        header.configureFor(eventCount: events.count, firstEvent: events.first, lastEvent: events.last, midnightUTCDate: midnightUTCDate)
        header.apply(theme: theme)
        
        return header
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? OnThisDayCollectionViewCell else {
            return
        }
        cell.selectionDelegate = self
        cell.pauseDotsAnimation = false
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? OnThisDayCollectionViewCell else {
            return
        }
        cell.selectionDelegate = nil
        cell.pauseDotsAnimation = true
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
        guard indexPath.section == 0, elementKind == UICollectionView.elementKindSectionHeader else {
            return
        }
        isDateVisibleInTitle = false
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, didEndDisplayingSupplementaryView view: UICollectionReusableView, forElementOfKind elementKind: String, at indexPath: IndexPath) {
        guard indexPath.section == 0, elementKind == UICollectionView.elementKindSectionHeader else {
            return
        }
        isDateVisibleInTitle = true
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return false
    }
}



// MARK: - SideScrollingCollectionViewCellDelegate
extension OnThisDayViewController: SideScrollingCollectionViewCellDelegate {
    func sideScrollingCollectionViewCell(_ sideScrollingCollectionViewCell: SideScrollingCollectionViewCell, didSelectArticleWithURL articleURL: URL, at indexPath: IndexPath) {
        let index: Int?
        if let indexPath = collectionView.indexPath(for: sideScrollingCollectionViewCell) {
            index = indexPath.section - 1
        } else {
            index = nil
        }
        FeedFunnel.shared.logArticleInFeedDetailReadingStarted(for: feedFunnelContext, index: index, maxViewed: maxViewed)
        wmf_pushArticle(with: articleURL, dataStore: dataStore, theme: self.theme, animated: true)
    }
}

// MARK: - EventLoggingEventValuesProviding
extension OnThisDayViewController: EventLoggingEventValuesProviding {
    var eventLoggingCategory: EventLoggingCategory {
        return .feed
    }
    
    var eventLoggingLabel: EventLoggingLabel? {
        return .onThisDay
    }
}

// MARK: - WMFArticlePreviewingActionsDelegate
extension OnThisDayViewController {
    override func shareArticlePreviewActionSelected(withArticleController articleController: WMFArticleViewController, shareActivityController: UIActivityViewController) {
        FeedFunnel.shared.logFeedDetailShareTapped(for: feedFunnelContext, index: previewedIndex)
        super.shareArticlePreviewActionSelected(withArticleController: articleController, shareActivityController: shareActivityController)
    }

    override func readMoreArticlePreviewActionSelected(withArticleController articleController: WMFArticleViewController) {
        articleController.wmf_removePeekableChildViewControllers()
        wmf_push(articleController, context: feedFunnelContext, index: previewedIndex, animated: true)
    }
}
