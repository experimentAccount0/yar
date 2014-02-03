{
	"language": "javascript",
	"views": {
		"all": {
			"map": "function(doc) { if (doc.type.match(/^creds_v\\d+.\\d+/i)) emit(doc._id, doc) }"
		},
		"by_owner": {
			"map": "function(doc) { if (doc.type.match(/^creds_v\\d+.\\d+/i)) emit(doc.owner, doc) }"
		}
	}
}