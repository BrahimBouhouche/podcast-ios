//
//  RecommendedSeriesTableViewCell.swift
//  Podcast
//
//  Created by Kevin Greer on 2/19/17.
//  Copyright © 2017 Cornell App Development. All rights reserved.
//

import UIKit

protocol RecommendedSeriesTableViewCellDataSource {
    func recommendedSeriesTableViewCell(dataForItemAt indexPath: IndexPath) -> Series
    func numberOfRecommendedSeries() -> Int
}

protocol RecommendedSeriesTableViewCellDelegate{
    func recommendedSeriesTableViewCell(didSelectItemAt indexPath: IndexPath)
}

class RecommendedSeriesTableViewCell: UITableViewCell, UICollectionViewDelegate, UICollectionViewDataSource {
    
    var collectionView: UICollectionView!
    var dataSource: RecommendedSeriesTableViewCellDataSource?
    var delegate: RecommendedSeriesTableViewCellDelegate?
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        collectionView = UICollectionView(frame: bounds, collectionViewLayout: RecommendedSeriesCollectionViewFlowLayout())
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = .clear
        backgroundColor = .clear
        collectionView.register(RecommendedSeriesCollectionViewCell.self, forCellWithReuseIdentifier: "Cell")
        collectionView.showsHorizontalScrollIndicator = false
        contentView.addSubview(collectionView)
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataSource?.numberOfRecommendedSeries() ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! RecommendedSeriesCollectionViewCell
        let series = dataSource?.recommendedSeriesTableViewCell(dataForItemAt: indexPath) ?? Series()
        cell.configure(series: series)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.recommendedSeriesTableViewCell(didSelectItemAt: indexPath)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
        collectionView.layoutSubviews()
        collectionView.setNeedsLayout()
    }
}
