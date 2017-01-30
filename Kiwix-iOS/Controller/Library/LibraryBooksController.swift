//
//  LibraryBooksController.swift
//  Kiwix
//
//  Created by Chris Li on 1/23/17.
//  Copyright © 2017 Chris Li. All rights reserved.
//

import UIKit
import CoreData
import ProcedureKit
import DZNEmptyDataSet

class LibraryBooksController: CoreDataCollectionBaseController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, LibraryCollectionCellDelegate {
    private(set) var itemWidth: CGFloat = 0.0
    var isCloudTab = true {
        didSet {
            title = isCloudTab ? Localized.Library.cloudTitle : Localized.Library.localTitle
            tabBarItem.image = UIImage(named: isCloudTab ? "Cloud" : "Folder")
            tabBarItem.selectedImage = UIImage(named: isCloudTab ? "CloudFilled" : "FolderFilled")
        }
    }
    
    func configureCollectionViewLayout() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {return}
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
    }
    
    func configureItemWidth(collectionViewWidth: CGFloat) {
        let itemsPerRow = (collectionViewWidth / 320).rounded()
        itemWidth = (collectionViewWidth - 1 * (itemsPerRow - 1)) / itemsPerRow
    }
    
    // MARK: - Override
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureBarButtons()
        configureCollectionViewLayout()
        if isCloudTab { configureRefreshControl() }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isCloudTab { refreshAutomatically() }
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureItemWidth(collectionViewWidth: collectionView.frame.width)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        configureItemWidth(collectionViewWidth: size.width)
        collectionView?.collectionViewLayout.invalidateLayout()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showLangFilter" {
            let nav = segue.destination as? UINavigationController
            let controller = nav?.topViewController as? LibraryLanguageController
            controller?.dismissBlock = {[unowned self] in
                self.reloadFetchedResultController()
            }
        }
    }
    
    // MARK: - UIControls
    
    let languageFilterButton = UIBarButtonItem(image: UIImage(named: "LanguageFilter"), style: .plain, target: nil, action: nil)
    let downlaodButton = UIBarButtonItem(image: UIImage(named: "Download"), style: .plain, target: nil, action: nil)
    @IBAction func dismissButtonTapped(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }
    
    func configureBarButtons() {
        if isCloudTab {
            languageFilterButton.target = self
            languageFilterButton.action = #selector(languageFilterButtonTapped(sender:))
            downlaodButton.target = self
            downlaodButton.action = #selector(downloadButtonTapped(sender:))
            navigationItem.rightBarButtonItems = [languageFilterButton, downlaodButton]
        } else {
            navigationItem.rightBarButtonItem = editButtonItem
        }
    }
    
    func languageFilterButtonTapped(sender: UIBarButtonItem) {
        let controller = UIStoryboard(name: "Library", bundle: nil).instantiateViewController(withIdentifier: "LibraryLanguageNavController")
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.barButtonItem = sender
        present(controller, animated: true, completion: nil)
    }
    
    func downloadButtonTapped(sender: UIBarButtonItem) {
        let controller = UIStoryboard(name: "Library", bundle: nil).instantiateViewController(withIdentifier: "LibraryDownloadNavController")
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.barButtonItem = sender
        present(controller, animated: true, completion: nil)
    }
    
    // MARK: - Refresh
    
    private(set) var isRefreshing = false // used to control text on empty table view
    
    private func configureRefreshControl() {
        collectionView.refreshControl = RefreshLibControl()
        collectionView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
    }
    
    func refreshAutomatically() {
        guard let date = Preference.libraryLastRefreshTime else { refresh(); return }
        guard date.timeIntervalSinceNow < -86400 else {return}
        refresh()
    }
    
    func refresh() {
        let operation = RefreshLibraryOperation()
        operation.add(observer: WillExecuteObserver { (operation) in
            OperationQueue.main.addOperation({
                // Configure empty table data set, so it shows "Refreshing..."
                self.isRefreshing = true
                self.collectionView.reloadEmptyDataSet()
            })
        })
        operation.add(observer: DidFinishObserver { (operation, errors) in
            guard let operation = operation as? RefreshLibraryOperation else {return}
            OperationQueue.main.addOperation({
                defer {
                    self.collectionView.refreshControl?.endRefreshing()
                    self.isRefreshing = false
                    self.collectionView.reloadEmptyDataSet()
                }
                
                if let _ =  errors.first {
                    // handle error [network, xmlparse]
                } else {
                    if operation.firstTime {
                        //self.showLanguageFilterAlert()
                        //self.configureNavBarButtons()
                    } else {
//                        self.showRefreshSuccessMessage()
                    }
                }
            })
        })
        GlobalQueue.shared.add(operation: operation)
    }
    
    // MARK: - UICollectionView Data Source
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return fetchedResultController.sections?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return fetchedResultController.sections?[section].numberOfObjects ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! LibraryCollectionCell
        
        let book = fetchedResultController.object(at: indexPath)
        cell.delegate = self
        cell.imageView.image = UIImage(data: book.favIcon ?? Data())
        cell.titleLabel.text = book.title
        cell.subtitleLabel.text = [
            book.dateDescription,
            book.fileSizeDescription,
            book.articleCountDescription
        ].flatMap({$0}).joined(separator: "  ")
        cell.descriptionLabel.text = book.desc
        cell.hasPicLabel.isHidden = !book.hasPic
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! LibraryCollectionHeader
        header.textLabel.text = fetchedResultController.sections?[indexPath.section].name
        return header
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: itemWidth, height: 66)
    }
    
    // MARK: - LibraryCollectionCellDelegate
    
    func didTapMoreButton(cell: LibraryCollectionCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else {return}
        let book = fetchedResultController.object(at: indexPath)
        
        let procedure = AlertProcedure.bookMore(context: self, book: book)
        procedure.alert.modalPresentationStyle = .popover
        procedure.alert.popoverPresentationController?.sourceView = cell.moreButton
        procedure.alert.popoverPresentationController?.sourceRect = cell.moreButton.bounds
        UIQueue.shared.add(operation: procedure)
    }
    
    // MARK: - NSFetchedResultsController
    
    let managedObjectContext = AppDelegate.persistentContainer.viewContext
    lazy var fetchedResultController: NSFetchedResultsController<Book> = {
        let fetchRequest = Book.fetchRequest()
        let langDescriptor = NSSortDescriptor(key: "language.name", ascending: true)
        let titleDescriptor = NSSortDescriptor(key: "title", ascending: true)
        fetchRequest.sortDescriptors = [langDescriptor, titleDescriptor]
        fetchRequest.predicate = NSPredicate(format: "language.name != nil")
        fetchRequest.predicate = self.predicate
        let controller = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                    managedObjectContext: self.managedObjectContext,
                                                    sectionNameKeyPath: "language.name", cacheName: nil)
        controller.delegate = self
        try? controller.performFetch()
        return controller as! NSFetchedResultsController<Book>
    }()
    
    var predicate: NSCompoundPredicate {
        if isCloudTab {
            let displayedLanguages = Language.fetch(displayed: true, context: managedObjectContext)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "stateRaw == 0"),
                displayedLanguages.count > 0 ? NSPredicate(format: "language IN %@", displayedLanguages) : NSPredicate(format: "language.name != nil")
            ])
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [NSPredicate(format: "stateRaw == 2")])
        }
    }
    
    func reloadFetchedResultController() {
        fetchedResultController.fetchRequest.predicate = predicate
        NSFetchedResultsController<Book>.deleteCache(withName: fetchedResultController.cacheName)
        try? fetchedResultController.performFetch()
        collectionView.reloadData()
    }

}

extension Localized {
    class Library {
        static let cloudTitle = NSLocalizedString("Cloud", comment: "Library, Cloud")
        static let localTitle = NSLocalizedString("Local", comment: "Library, Local")
        
        static let download = NSLocalizedString("Download", comment: "Library, more action sheet")
        static let copyURL = NSLocalizedString("Copy URL", comment: "Library, more action sheet")
    }
}
