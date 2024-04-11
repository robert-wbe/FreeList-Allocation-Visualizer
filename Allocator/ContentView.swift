//
//  ContentView.swift
//  Allocator
//
//  Created by Robert Wiebe on 12/17/23.
//

import SwiftUI

class Allocator: ObservableObject {
    typealias AdrSize = UInt8
    private static let infoSegSize: AdrSize = 3
    private static let sizeOffset: AdrSize = 0
    private static let nextFreeOffset: AdrSize = 1
    private static let lastFreeOffset: AdrSize = 2
    private static let nullCode: AdrSize = AdrSize.max
    
    @Published var heapMem: [UInt8]
    private var firstFree: AdrSize = 0
    
    init(heapSize: AdrSize) {
        heapMem = .init(repeating: 0, count: Int(heapSize) + 1)
        
        // setup of the initial block's info segment
        heapMem[0] = heapSize - Self.infoSegSize + 1
        heapMem[1] = Self.nullCode
        heapMem[2] = Self.nullCode
    }
    
    public func malloc(size: AdrSize) -> AdrSize? {
        let neededSplitSize = size + Self.infoSegSize + 1
        var blockPtr: AdrSize = firstFree
        
        while blockPtr != Self.nullCode {
            let blockSize = getSize(ptr: blockPtr)
            
            if blockSize < size {
                blockPtr = getNextFree(ptr: blockPtr) ?? Self.nullCode
                continue
            }
            
            if blockSize < neededSplitSize {
                removeFromFreeList(blockPtr)
                if (blockPtr == firstFree) {
                    firstFree = getNextFree(ptr: blockPtr) ?? Self.nullCode
                }
                return getDataPtr(ptr: blockPtr)
            }
            
            // introduction of 1 new block
            let newBlock = getDataPtr(ptr: blockPtr) + size
            setSize(ptr: newBlock, blockSize - size - Self.infoSegSize)
            setNext(ptr: newBlock, getNextFree(ptr: blockPtr) ?? Self.nullCode)
            setLast(ptr: newBlock, getLastFree(ptr: blockPtr) ?? Self.nullCode)
            
            setSize(ptr: blockPtr, size)
            setNext(ptr: blockPtr, newBlock)
            addToFreeList(newBlock)
            if (blockPtr == firstFree) {
                firstFree = getNextFree(ptr: blockPtr) ?? Self.nullCode
            }
            return getDataPtr(ptr: blockPtr)
        }
        
        return nil
    }
    
    public func free(ptr: AdrSize) {
        let basePtr = ptr - Self.infoSegSize
        let neighborsFree = (succeedsFree(basePtr), precedesFree(basePtr))
        switch neighborsFree {
        case (false, false):
            addToFreeList(basePtr)
            firstFree = min(firstFree, basePtr)
            return
        case (false, true):
            let nextBlock = getNextFree(ptr: basePtr)!
            setSize(ptr: basePtr, getSize(ptr: basePtr) + getSize(ptr: nextBlock) + Self.infoSegSize)
            setNext(ptr: basePtr, getNextFree(ptr: nextBlock) ?? Self.nullCode)
            addToFreeList(basePtr)
            firstFree = min(firstFree, basePtr)
            return
        case (true, false):
            let lastBlock = getLastFree(ptr: basePtr)!
            setSize(ptr: lastBlock, getSize(ptr: lastBlock) + getSize(ptr: basePtr) + Self.infoSegSize)
            setNext(ptr: lastBlock, getNextFree(ptr: basePtr) ?? Self.nullCode)
            addToFreeList(lastBlock)
            return
        case (true, true):
            let lastBlock = getLastFree(ptr: basePtr)!
            let nextBlock = getNextFree(ptr: basePtr)!
            setSize(ptr: lastBlock, getSize(ptr: lastBlock) + getSize(ptr: basePtr) + getSize(ptr: nextBlock) + 2*Self.infoSegSize)
            setNext(ptr: lastBlock, getNextFree(ptr: nextBlock) ?? Self.nullCode)
            addToFreeList(lastBlock)
        }
    }
    
    public func getInfoColorMap(infoCol: Color, freeCol: Color, usedCol: Color) -> [Color] {
        var map = [Color](repeating: usedCol, count: heapMem.count)
        var curBlock: AdrSize = 0
        while curBlock != Self.nullCode {
            let i = Int(curBlock)
            for iOff in 0..<Int(Self.infoSegSize) {
                map[i+iOff] = infoCol
            }
            curBlock = getNext(ptr: curBlock) ?? Self.nullCode
        }
        curBlock = firstFree
        while curBlock != Self.nullCode {
            let i = Int(curBlock)
            for iOff in 0..<Int(getSize(ptr: curBlock)) {
                map[i+Int(Self.infoSegSize)+iOff] = freeCol
            }
            curBlock = getNextFree(ptr: curBlock) ?? Self.nullCode
        }
        return map
    }
    
    private func getSize(ptr: AdrSize) -> AdrSize {
        heapMem[Int(ptr+Self.sizeOffset)]
    }
    
    private func getNextFree(ptr: AdrSize) -> AdrSize? {
        let byte = heapMem[Int(ptr+Self.nextFreeOffset)]
        if byte == Self.nullCode { return nil }
        return byte
    }
    
    private func getLastFree(ptr: AdrSize) -> AdrSize? {
        let byte = heapMem[Int(ptr+Self.lastFreeOffset)]
        if byte == Self.nullCode { return nil }
        return byte
    }
    
    private func getDataPtr(ptr: AdrSize) -> AdrSize {
        ptr + Self.infoSegSize
    }
    
    private func getNext(ptr: AdrSize) -> AdrSize? {
        let size = getSize(ptr: ptr)
        if Int(ptr) + Int(Self.infoSegSize) + Int(size) >= heapMem.count {
            return nil
        }
        return ptr + Self.infoSegSize + size
    }
    
    private func setSize(ptr: AdrSize, _ size: AdrSize) {
        heapMem[Int(ptr+Self.sizeOffset)] = size
    }
    
    private func setNext(ptr: AdrSize, _ next: AdrSize) {
        heapMem[Int(ptr+Self.nextFreeOffset)] = next
    }
    
    private func setLast(ptr: AdrSize, _ last: AdrSize) {
        heapMem[Int(ptr+Self.lastFreeOffset)] = last
    }
    
    private func removeFromFreeList(_ ptr: AdrSize) {
        if let lastFree = getLastFree(ptr: ptr) {
            let newNext = getNextFree(ptr: ptr) ?? Self.nullCode
            var curBlock = lastFree
            while curBlock != ptr {
                setNext(ptr: curBlock, newNext)
                curBlock = getNext(ptr: curBlock)!
            }
            setNext(ptr: ptr, newNext)
        }
        else {
            let newNext = getNextFree(ptr: ptr) ?? Self.nullCode
            var curBlock: AdrSize = 0
            while curBlock != ptr {
                setNext(ptr: curBlock, newNext)
                curBlock = getNext(ptr: curBlock)!
            }
            setNext(ptr: ptr, newNext)
        }
        if let nextFree = getNextFree(ptr: ptr) {
            let newLast = getLastFree(ptr: ptr) ?? Self.nullCode
            var curBlock = ptr
            while curBlock != nextFree {
                setLast(ptr: curBlock, newLast)
                curBlock = getNext(ptr: curBlock)!
            }
            setLast(ptr: nextFree, newLast)
        }
        else {
            let newLast = getLastFree(ptr: ptr) ?? Self.nullCode
            var curBlock = ptr
            while curBlock != Self.nullCode {
                setLast(ptr: curBlock, newLast)
                curBlock = getNext(ptr: curBlock) ?? Self.nullCode
            }
        }
    }
    
    private func addToFreeList(_ ptr: AdrSize) {
        if let lastFree = getLastFree(ptr: ptr) {
            var curBlock = lastFree
            while curBlock != ptr {
                setNext(ptr: curBlock, ptr)
                curBlock = getNext(ptr: curBlock)!
            }
        }
        else {
            var curBlock: AdrSize = 0
            while curBlock != ptr {
                setNext(ptr: curBlock, ptr)
                curBlock = getNext(ptr: curBlock)!
            }
        }
        if let nextFree = getNextFree(ptr: ptr) {
            var curBlock = getNext(ptr: ptr)!
            while curBlock != nextFree {
                setLast(ptr: curBlock, ptr)
                curBlock = getNext(ptr: curBlock)!
            }
            setLast(ptr: nextFree, ptr)
        }
        else {
            var curBlock = getNext(ptr: ptr) ?? Self.nullCode
            while curBlock != Self.nullCode {
                setLast(ptr: curBlock, ptr)
                curBlock = getNext(ptr: curBlock) ?? Self.nullCode
            }
        }
    }
    
    private func precedesFree(_ ptr: AdrSize) -> Bool {
        guard let nextFree = getNextFree(ptr: ptr) else { return false }
        return ptr + getSize(ptr: ptr) + Self.infoSegSize == nextFree
    }
    
    private func succeedsFree(_ ptr: AdrSize) -> Bool {
        guard let lastFree = getLastFree(ptr: ptr) else { return false}
        return lastFree + getSize(ptr: lastFree) + Self.infoSegSize == ptr
    }
}

struct HeapView: View {
    @ObservedObject var allocator: Allocator
    let rowLength: Int
    let gridSpacing: CGFloat = 2.0
    
    static let infoColor: Color = .blue
    static let freeColor: Color = .init(red: 46/255, green: 125/255, blue: 50/255)
    static let ocpColor: Color = .red
    
    enum DisplayStyle: CaseIterable, CustomStringConvertible {
        case hex, dec, ascii
        
        var description: String {
            switch self {
            case .hex:
                "Hexadecimal"
            case .dec:
                "Decimal"
            case .ascii:
                "Ascii"
            }
        }
    }
    @Binding var displayStyle: DisplayStyle
    
    var body: some View {
        let colorMap = allocator.getInfoColorMap(infoCol: Self.infoColor, freeCol: Self.freeColor, usedCol: Self.ocpColor)
        LazyVGrid(columns: Array(repeating: .init(.flexible(minimum: 30, maximum: 50), spacing: gridSpacing), count: rowLength)) {
            ForEach(0..<allocator.heapMem.count, id: \.self) { i in
                Text(formatByte(byte: allocator.heapMem[i]))
                    .font(.custom("Source Code Pro", size: 14))
                    .fontWeight(.semibold)
                    .background {
                        colorMap[i]
                    }
            }
        }
    }
    
    func formatByte(byte: UInt8) -> String {
        switch displayStyle {
        case .hex:
            return String(format: "%02X", byte)
        case .dec:
            return String(format: "%03D", byte)
        case .ascii:
            let char = Character(UnicodeScalar(byte))
            if char.isLetter || char.isSymbol || char.isNumber || char.isPunctuation || char == " " { return String(char) }
            return String(format: "\\%02X", byte)
        }
    }
}

struct ContentView: View {
    @StateObject var allocator = Allocator(heapSize: 255)
    @State var inputSize: Allocator.AdrSize = 0
    @State var inputFreeLoc: Allocator.AdrSize = 0
    @State var blockMap: [Allocator.AdrSize:Allocator.AdrSize] = [:]
    @State var displayStyle: HeapView.DisplayStyle = .hex
    @State var inputText: String = ""
    @State var inputWriteLoc: Int = 0
    
    var body: some View {
        VStack {
            HeapView(allocator: allocator, rowLength: 16, displayStyle: $displayStyle)
            Divider()
            HStack {
                Text("Allocated blocks:")
                ForEach(blockMap.sorted(by: <), id: \.key) {loc, size in
                    Text("\(loc) (\(size) b)")
                }
            }
            Divider()
            HStack {
                VStack(alignment: .trailing) {
                    HStack {
                        Stepper("Allocation Size: \(inputSize)", value: $inputSize)
                        Button("Allocate") {
                            if let ptr = allocator.malloc(size: inputSize) {
                                blockMap[ptr] = inputSize
                                print("Allocated \(inputSize) bytes at \(ptr)")
                            }
                            else {
                                print("Allocation failed. Heap out of memory.")
                            }
                        }
                    }
                    HStack {
                        Stepper("Free Location \(inputFreeLoc)", value: $inputFreeLoc)
                        Button("Free") {
                            allocator.free(ptr: inputFreeLoc)
                            blockMap.removeValue(forKey: inputFreeLoc)
                            print("Freed \(inputFreeLoc)")
                        }
                    }
                }
                Divider()
                HStack {
                    Picker("Display Style", selection: $displayStyle) {
                        ForEach(HeapView.DisplayStyle.allCases, id: \.self) {
                            Text($0.description).tag($0)
                        }
                    }.pickerStyle(.radioGroup)
                }
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Rectangle()
                            .frame(width: 20, height: 10)
                            .foregroundStyle(HeapView.freeColor)
                        Text("free")
                    }
                    HStack {
                        Rectangle()
                            .frame(width: 20, height: 10)
                            .foregroundStyle(HeapView.ocpColor)
                        Text("occupied")
                    }
                    HStack {
                        Rectangle()
                            .frame(width: 20, height: 10)
                            .foregroundStyle(HeapView.infoColor)
                        Text("info block")
                    }
                }
            }
            Divider()
            HStack {
                TextField("Write Text Data", text: $inputText)
                Stepper("at location \(inputWriteLoc)", value: $inputWriteLoc)
                Button("Write") {
                    for (i, char) in inputText.enumerated() {
                        allocator.heapMem[inputWriteLoc + i] = char.asciiValue!
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
