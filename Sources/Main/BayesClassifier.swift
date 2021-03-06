/**
* @Author: AJ Ibraheem <AJ>
* @Date:   2016-02-20T08:50:02+00:00
* @Email:  ibraheemaj@icloud.com
* @Last modified by:   AJ
* @Last modified time: 2016-02-20T09:35:25+00:00
*/

import Foundation

/**
    a classifier will be built from files with the bucketPrefix excluding the file with
    textBucketNumber. dataFormat is a string that describes how to interpret each line of the data files.
    For example, for the iHealth data the format is: "attr     attr  attr  attr  class"
    - note
        * This BayesClassifier seems to be having lots of similarites to the Classifier class, a todo might be to inherit from the classifier class
        * Another extension could be to use typealias(es) to simplify the dictionary definitions e.g counts[Category:[Column:[DataItem:Count]]]
    - todo
        - [x] Use a parser that inherits from the DataParser protocol instead and modify the data parser protocol to include attributes:[String] alongside vectors
        - [x] Following the examples from the book, let totals `totalsColumn` be based off numericValues `numericValuesColumn`
*/
class BayesClassifier {

    typealias Classification = String
    typealias Column = Int
    typealias Attribute = String
    typealias Probability = Double

    let numOfBuckets = 10

    var classes:[String:Int] = [:] //Counts the occurrence of each class or category
    var counts:[String:[Int:[String:Int]]] = [:] //tracks the occurrence of each attribute that are not numeric values in the different columns
    var data: [(classification:String, attribute:[String], vector:[Double], ignore:[String])] = []
    var total:Int { return data.count } //track the number of rows we processed
    var numericValuesColumn:[Classification:[Column:[Double]]] = [:] //the numeric values for each column mapped by the classes
    var totalsColumn:[Classification:[Column:Double]] = [:] //the sum total of all vaues for the current column mapped by classes

    lazy var priorProbability: [String:Double] = {
        //Calculates the Prior Probability p(h) for every category in classes
        return self.classes.keys.reduce([:], combine:{ (probabilities:[Classification:Probability],category:String) in
            var result = probabilities
            result[category] = Double(self.classes[category]!) / Double(self.total)
            return result
        })
    }()
    lazy var conditionalProbability: [Classification:[Column:[Attribute:Probability]]] = {
        //Compute the conditional probability for the Hypothesis given Data p(h|D)
        //Column number is being used to preserve integrity of each attribute as they might repeat across columns
        //Probs i could have gone functional and used `reduce` ? 🤔🤔🤔
        var result:[Classification:[Column:[Attribute:Probability]]] = [:]
        for (category,column) in self.counts {
            result[category] = [:]
            for (cNo,attributeCount) in column {
                if result[category]![cNo] == nil { result[category]![cNo] = [:] }
                for (attribute,count) in attributeCount {
                    result[category]![cNo]![attribute] = Double(count) / Double(self.classes[category]!)
                }
            }
        }
        return result
    }()
    lazy var mean:[Classification:[Column:Double]] = {
        return self.totalsColumn.keys.reduce([:], combine:{ (mean:[Classification:[Column:Double]],category:Classification) in
            var result = mean //making it mutable 
            result[category] = [:]
            for( column,columnTotals ) in self.totalsColumn[category]! {
                result[category]![column] = Double(columnTotals) / Double(self.classes[category]!)
            }
            return result
        })
    }()
    lazy var sampleStandardDeviation:[Classification:[Column:Double]] = {
        return self.numericValuesColumn.keys.reduce([:], combine:{ (ssd:[Classification:[Column:Double]],category:Classification) in
            var _ssd = ssd
            _ssd[category] = [:] //NB: The Categories are unique
            for (column,values) in self.numericValuesColumn[category]! {
                let mean = self.mean[category]![column]!
                let sumSquareDifference = values.reduce(Double(0.0), combine:{ (cumulative,value) in
                    return cumulative + ((value - mean)^^2)
                })
                _ssd[category]![column] = sqrt( sumSquareDifference / Double(self.classes[category]! - 1) )
            }
            return _ssd
        })
    }()
    

    /**
        Trains the classifier and builds an internal model
        - parameter testBucketNumber: The Bucket number to use to test, counting starts from 0
    */
    init( bucketPrefix:String, testBucketNumber:Int, dataParser:DataParser ){
        //Read in the data
        for i in 0..<numOfBuckets {
            if i == testBucketNumber { continue }
            let filename = "Temp/\(bucketPrefix)-\(i).txt"
            self.data += dataParser.parseFile( filename )
        }

        //Process the entire collection and fill up the classes and counts variables
        _ = self.data.map({ rowData in
            if classes[rowData.classification] == nil {
                classes[rowData.classification] = 0
                counts[rowData.classification] = [:]
            }
            classes[rowData.classification]! += 1
            
            let category = rowData.classification
            //Process each attribute/vector for the current rowData
            var column:Int = 0
            for attrib in rowData.attribute {
                column += 1
                if counts[category]![column] == nil { counts[category]![column] = [:] }
                if counts[category]![column]![attrib] == nil { counts[category]![column]![attrib] = 0 }
                counts[category]![column]![attrib]! += 1
            }
            //Process each non-numeric attribute for the rowData/row 
            column = 0
            for vector in rowData.vector {
                column += 1
                if totalsColumn[category] == nil { totalsColumn[category] = [:] }
                if totalsColumn[category]![column] == nil { totalsColumn[category]![column] = 0 }
                if numericValuesColumn[category] == nil { numericValuesColumn[category] = [:] }
                if numericValuesColumn[category]![column] == nil { numericValuesColumn[category]![column] = [] }
                numericValuesColumn[category]![column]! += [vector]
                totalsColumn[category]![column]! += vector
            }
        })//end map
    }//end init

    /**
        Probability Density function calculating P(x|y) i.e probability of x given y, very useful for classifying attributes with
        numeric values 
        - parameter mean: The average of all data in the **sample set**
        - parameter standardDeviation: **standardDeviation here is actually the sample standard deviation**
        - parameter x: The Hypothesis we are testing
        - note:
            * Infix operator ^^ declared in utilities.swift which is the power function
            * M_E is a constant equals to Euler's constant 𝑒 in Swift ofcourse :)
            * M_PI is the equivalent of Pi π
    */
    func probabilityDensity( mean mean:Double, standardDeviation:Double, x:Double ) -> Double {
        let ePart = M_E ^^ ( (-((x - mean) ^^ 2)) / (2 * (standardDeviation ^^ 2)) )
        return (1.0/(sqrt(2 * M_PI)*standardDeviation)) * ePart
    }

    /**
        A Stub method usually used in cross validation, parses and classifies the data in the current bucket
        and returns the result
        - parameter bucketFileName: The URL of the bucket to read data from
        - parameter parser: The Parser to use when parsing the data read in bucket `bucketFileName`
        - note :
            **This method would be deprecated soon when BayesClassifier and Classifier get merged or refactored
    */
    func testBucket( bucketFileName:String , parser:DataParser ) -> [String:[String:Int]]{
        var totals: [String:[String:Int]] = [:]
        let data = parser.parseFile( bucketFileName );

        for datum in data {
            let realClass = datum.classification
            let classifiedAs = self.classify( datum.attribute, numericVector:datum.vector )
            if totals[realClass] == nil { totals[realClass] = [:] }
            if totals[realClass]![classifiedAs] == nil { totals[realClass]![classifiedAs] = 0 }

            totals[realClass]![classifiedAs]! += 1
        }

        return totals
    }

    /**
        Makes a classification based on the `attributeVector` by computing the maximum a posteriori
        probability of each Hypothesis and returning the maximum probability
        - todo: 
            - [x] Add a numericVector parameter to the function
        - note: Presently `Attribute` is a string and as a result, the classifier would not classify data
            with Integer/Double attributes **This needs to be improved**
        - parameter attributeVector: The array of attributes to base the classification on
    */
    func classify( attributeVector:[Attribute], numericVector:[Double] ) -> Classification {
        return self.priorProbability.keys
            .reduce( [(Classification,Probability)](), combine:{
                (results:[(Classification,Probability)], category:String) in
                var temp = results
                var probability = self.priorProbability[category]!
                var column = 1
                _ = attributeVector.map({ attribute in
                    if let prob = self.conditionalProbability[category]![column]![attribute] {
                        probability *= prob;
                        column += 1
                    }else{ probability = 0 }
                })
                column = 1
                _ = numericVector.map({ numeric in
                    let mean = self.mean[category]![column]!
                    let standardDeviation = self.sampleStandardDeviation[category]![column]!
                    probability *= probabilityDensity( mean:mean, standardDeviation:standardDeviation, x:numeric )
                    column += 1 
                })
                temp += [(category,probability)]
                return temp
            })
            .sort({ $0.1 > $1.1 }) //Sort based on probability in tuple
            .first!.0 // 0 is Classification
    }
}
