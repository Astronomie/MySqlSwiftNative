//
//  Rows.swift
//  mysql_driver
//
//  Created by cipi on 23/12/15.
//  Copyright © 2015 cipi. All rights reserved.
//

import Foundation

public protocol Result {
    init(con:MySQL.Connection)
    func readRow() throws -> MySQL.Row?
    func readAllRows() throws -> [MySQL.RowArray]?
}

extension MySQL {
    
    public typealias Row = [String:Any?]
    public typealias RowArray = [Row]
    
    class TextRow: Result {
        
        var con:Connection
        
        required init(con:Connection) {
            self.con = con
        }
        
        func readRow() throws -> MySQL.Row?{
            
            guard con.isConnected == true else {
                throw Connection.Error.NotConnected
            }
            
            if con.columns?.count == 0 {
                con.hasMoreResults = false
                con.EOFfound = true
            }
            
            if !con.EOFfound, let cols = con.columns where cols.count > 0, let data = try con.socket?.readPacket()  {
                
       /*
                for val in data {
                    let u = UnicodeScalar(val)
                    print(Character(u))
                }
*/
                
                // EOF Packet
                if (data[0] == 0xfe) && (data.count == 5) {
                    con.EOFfound = true
                    let flags = Array(data[3..<5]).uInt16()
                    
                    if flags & MysqlServerStatus.SERVER_MORE_RESULTS_EXISTS == MysqlServerStatus.SERVER_MORE_RESULTS_EXISTS {
                        con.hasMoreResults = true
                    }
                    else {
                        con.hasMoreResults = false
                    }

                    return nil
                }
                
                if data[0] == 0xff {
                    throw con.handleErrorPacket(data)
                }
                
                var row = [String:Any?]()
                var pos = 0
                
                if cols.count > 0 {
                    for i in 0...cols.count-1 {
                        let (name, n) = MySQL.Utils.lenEncStr(Array(data[pos..<data.count]))
                        pos += n
                        
                        if let val = name {
                            switch cols[i].fieldType {
                            case MysqlTypes.MYSQL_TYPE_VAR_STRING:
                                row[cols[i].name] = name
                                break
                            case MysqlTypes.MYSQL_TYPE_LONG, MysqlTypes.MYSQL_TYPE_LONGLONG,
                            MysqlTypes.MYSQL_TYPE_TINY, MysqlTypes.MYSQL_TYPE_SHORT:
                                row[cols[i].name] = Int(val)
                                break
                            case MysqlTypes.MYSQL_TYPE_DOUBLE, MysqlTypes.MYSQL_TYPE_FLOAT:
                                row[cols[i].name] = Double(val)
                                break
                            case MysqlTypes.MYSQL_TYPE_NULL:
                                row[cols[i].name] = NSNull()
                                break
                            default:
                                row[cols[i].name] = NSNull()
                                break
                            }
                            
                        }
                        else {
                            row[cols[i].name] = NSNull()
                        }
                    }
                }
                
                return row
            }
            
            return nil

        }
        
        func readAllRows() throws -> [RowArray]? {
            
            var arr = [RowArray]()
            
            repeat {
                
                if con.hasMoreResults {
                    try con.nextResult()
                }
                
                var rows = RowArray()
                
                while let row = try readRow() {
                    rows.append(row)
                }
                
                if (rows.count > 0){
                    arr.append(rows)
                }
                
            } while con.hasMoreResults
            
            return arr
        }
    }
    
    class BinaryRow: Result {
        
        private var con:Connection
        
        required init(con:Connection) {
            self.con = con
        }
        
        func readRow() throws -> MySQL.Row?{
            
            guard con.isConnected == true else {
                throw Connection.Error.NotConnected
            }
            
            if con.columns?.count == 0 {
                con.hasMoreResults = false
                con.EOFfound = true
            }
            
            if !con.EOFfound, let cols = con.columns where cols.count > 0, let data = try con.socket?.readPacket() {
                                
                //OK Packet
                if data[0] != 0x00 {
                    // EOF Packet
                    if (data[0] == 0xfe) && (data.count == 5) {
                        con.EOFfound = true
                        let flags = Array(data[3..<5]).uInt16()
                        
                        if flags & MysqlServerStatus.SERVER_MORE_RESULTS_EXISTS == MysqlServerStatus.SERVER_MORE_RESULTS_EXISTS {
                            con.hasMoreResults = true
                        }
                        else {
                            con.hasMoreResults = false
                        }
                        
                        return nil
                    }
                    
                    //Error packet
                    if data[0] == 0xff {
                        throw con.handleErrorPacket(data)
                    }
                    
                    return nil
                }
                
                var pos = 1 + (cols.count + 7 + 2)>>3
                let nullBitmap = Array(data[1..<pos])
                var row = Row()
                
                for i in 0..<cols.count {
                    
                    let idx = (i+2)>>3
                    let shiftval = UInt8((i+2)&7)
                    let val = nullBitmap[idx] >> shiftval
                    
                    if (val & 1) == 1 {
                        row[cols[i].name] = NSNull()
                        continue
                    }
                    
                    switch cols[i].fieldType {
                        
                    case MysqlTypes.MYSQL_TYPE_NULL:
                        row[cols[i].name] = NSNull()
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_TINY:
                        row[cols[i].name] = Int8(data[pos])
                        pos += 1
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_SHORT, MysqlTypes.MYSQL_TYPE_SHORT:
                        row[cols[i].name] = data[pos..<pos+2].int16()
                        pos += 2
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_INT24, MysqlTypes.MYSQL_TYPE_LONG:
                        row[cols[i].name] = data[pos..<pos+4].int32()
                        pos += 4
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_LONGLONG:
                        row[cols[i].name] = data[pos..<pos+8].int64()
                        pos += 8
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_FLOAT:
                        row[cols[i].name] = data[pos..<pos+4].float32()
                        pos += 4
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_DOUBLE:
                        row[cols[i].name] = data[pos..<pos+8].float64()
                        pos += 8
                        break

                    case MysqlTypes.MYSQL_TYPE_DECIMAL, MysqlTypes.MYSQL_TYPE_NEWDECIMAL, MysqlTypes.MYSQL_TYPE_VARCHAR,
                        MysqlTypes.MYSQL_TYPE_BIT, MysqlTypes.MYSQL_TYPE_ENUM, MysqlTypes.MYSQL_TYPE_SET, MysqlTypes.MYSQL_TYPE_TINY_BLOB,
                        MysqlTypes.MYSQL_TYPE_MEDIUM_BLOB, MysqlTypes.MYSQL_TYPE_LONG_BLOB, MysqlTypes.MYSQL_TYPE_BLOB,
                        MysqlTypes.MYSQL_TYPE_VAR_STRING, MysqlTypes.MYSQL_TYPE_STRING, MysqlTypes.MYSQL_TYPE_GEOMETRY:
                        
                        let (str, n) = MySQL.Utils.lenEncStr(Array(data[pos..<data.count]))
                        row[cols[i].name] = str
                        pos += n
                        break
                        
                    case MysqlTypes.MYSQL_TYPE_DATE, MysqlTypes.MYSQL_TYPE_NEWDATE, MysqlTypes.MYSQL_TYPE_TIME,
                        MysqlTypes.MYSQL_TYPE_TIMESTAMP, MysqlTypes.MYSQL_TYPE_DATETIME:
                        
                        let (num, n) = MySQL.Utils.lenEncInt(Array(data[pos..<data.count]))
                        row[cols[i].name] = num
                        pos += n
                        break
                    default:
                        row[cols[i].name] = NSNull()
                        break
                    }
                    
                }
                return row
            }
            
            return nil
        }
        
        func readAllRows() throws -> [RowArray]? {
            
            var arr = [RowArray]()
            
            repeat {
            
                if con.hasMoreResults {
                    try con.nextResult()
                }
            
                var rows = RowArray()
                
                while let row = try readRow() {
                    rows.append(row)
                }
                if (rows.count > 0){
                    arr.append(rows)
                }
                
                
            } while con.hasMoreResults
            
            return arr
        }
    }
}