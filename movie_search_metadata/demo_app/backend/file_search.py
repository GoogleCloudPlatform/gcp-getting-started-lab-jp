from typing import List

from utils import get_bucket_and_blobnames
from utils import generate_download_signed_url_v4
from search_document import search_documents_by_query


def search_files(query: str) -> List[dict]:
    response = search_documents_by_query(query)
    results = []
    results.append({'summary': response.summary.summary_text})

    for c, item in enumerate(response.results):
        title = item.document.derived_struct_data['title']
        url = item.document.derived_struct_data['link']
        bucket_name, _, blob_mp4 = get_bucket_and_blobnames(url)
        signed_url = generate_download_signed_url_v4(bucket_name, blob_mp4)
        results.append({
            'id': c+1, 'title': title,
            'bucket_name': bucket_name, 'blob_name': blob_mp4,
            'url': url, 'signed_url': signed_url
        })

    return results
