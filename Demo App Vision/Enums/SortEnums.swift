// Define sorting options for catalog sorting

enum SortOption: String, CaseIterable, Identifiable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case newest = "Newest First"
    case oldest = "Oldest First"
    case categoryAsc = "Category"
    
    var id: String { rawValue }
}
