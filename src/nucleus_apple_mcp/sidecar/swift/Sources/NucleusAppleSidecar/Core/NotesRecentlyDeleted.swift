import Foundation

private let recentlyDeletedFolderNames: Set<String> = [
    "Recently Deleted",
    "Nylig slettet",
    "Senast raderade",
    "Senest slettet",
    "Zuletzt gelöscht",
    "Supprimés récemment",
    "Eliminados recientemente",
    "Eliminati di recente",
    "Recent verwijderd",
    "Ostatnio usunięte",
    "Недавно удалённые",
    "Apagados recentemente",
    "Apagadas recentemente",
    "最近删除",
    "最近刪除",
    "最近削除した項目",
    "최근 삭제된 항목",
    "Son Silinenler",
    "Äskettäin poistetut",
    "Nedávno smazané",
    "Πρόσφατα διαγραμμένα",
    "Nemrég töröltek",
    "Șterse recent",
    "Nedávno vymazané",
    "เพิ่งลบ",
    "Đã xóa gần đây",
    "Нещодавно видалені"
].map { $0.lowercased() }.reduce(into: Set<String>()) { acc, n in acc.insert(n) }

func isRecentlyDeletedFolderName(_ name: String) -> Bool {
    recentlyDeletedFolderNames.contains(name.lowercased())
}

