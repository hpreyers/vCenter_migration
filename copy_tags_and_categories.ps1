$sourceVC = 'ldnlxpvcsa1.vitol.com'
$destVC = 'ldnlxpvcenter.vitol.com'

$categories = Get-TagCategory -server $sourceVC
$tags = get-tag -server $sourceVC

foreach ($category in $categories) {
    New-TagCategory -Server $destVC -Name $category.Name -Description $category.Description -Cardinality $category.Cardinality -EntityType $category.EntityType
}

foreach ($tag in $tags) {
    New-Tag -Server $destVC -Name $tag.Name -Category $tag.Category.Name -Description $tag.Description
}
