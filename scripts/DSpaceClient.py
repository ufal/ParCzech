import os
import json
import glob
import argparse
import requests
from urllib.parse import quote_plus



class DSpaceClient:
    def __init__(self, base_url, username, password):
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.password = password
        self.session = requests.Session()
        self.token = None
        self.headers = {
            "Accept": "application/json",
            "X-DSpace-REST-API-Version": "7"
        }

    # -------------------------
    # LOGIN (with CSRF + encoded +)
    # -------------------------
    def login(self):
        # Step 1: GET CSRF token
        r = self.request("GET", self.base_url, headers={"Accept": "application/json"})
        if "dspace-xsrf-token" not in r.headers:
            raise Exception("CSRF token not provided by server!")
        #csrf_token = r.headers["dspace-xsrf-token"]

        # Step 2: POST login
        login_url = f"{self.base_url}/authn/login"
        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
        #    "X-XSRF-TOKEN": csrf_token,
            "Accept": "application/json"
        }

        data = f"user={quote_plus(self.username)}&password={quote_plus(self.password)}"
        r2 = self.request("POST", login_url, headers=headers, data=data)

        if r2.status_code != 200:
            raise Exception(f"Login failed {r2.status_code}: {r2.text}")

        csrf_token = r2.headers["dspace-xsrf-token"]

        # JWT Authorization header
        token = r2.headers.get("Authorization")
        if not token:
            raise Exception("Login succeeded but no Authorization token returned!")
        
        
        print("Logged in successfully.")
        #self.headers["X-XSRF-TOKEN"] = csrf_token
        #self.headers["Authorization"] = token
        return token


    def ensure_logged_in(self):
      if self.token is None:
        if not self.username or not self.password:
            raise Exception("Username/password required for login")
        self.token = self.login()
        self.request("GET",f"{self.base_url}/authn/status")
        #self.headers["Authorization"] = self.token

    # ---------------------------
    # SEARCH ITEM BY METADATA
    # ---------------------------
    def search_items(self, metadata_filter=[], collection_id=None):
      """
      Search items with optional metadata filter and optional collection filter.
      """
      url = f"{self.base_url}/discover/search/objects"
      params = {
          "page": 0,
          "size": 1000
      }

      # Filter by collection
      if collection_id:
          params["configuration"] = "collection"
          params["scope"] = collection_id

      # Filter by metadata
      for f in metadata_filter:
        params[f"f.{f['key']}"] =f"{f['value']},{f['operator'] or 'contains'}"
      
      self.print_curl("get", url, headers=self.headers, params=params)
      r = self.request("GET", url, headers=self.headers, params=params)
      r.raise_for_status()
      return r.json()
    
    # ---------------------------
    # GET NEWEST VERSION
    # ---------------------------
    def get_latest_version(self, uuid):
        """Return UUID of the newest version of an item."""
        url = f"{self.base_url}/core/items/{uuid}"

        r = self.request("GET", url, headers=self.headers)
        if r.status_code != 200:
            raise Exception(f"Cannot get item: {r.status_code} {r.text}")

        item = r.json()
        
        # If this is already the newest version → return itself
        if item.get("version", {}).get("latest", True):
            return uuid
        
        # Otherwise follow "latestVersion"
        latest_link = item["_links"].get("latestVersion", {}).get("href")
        if not latest_link:
            return uuid  # fallback
        
        r2 = self.request("GET", latest_link, headers=self.headers)
        if r2.status_code != 200:
            return uuid
        
        return r2.json()["uuid"]


    # ---------------------------
    # DOWNLOAD METADATA
    # ---------------------------
    def export_metadata(self, item_uuid, output_path):
        url = f"{self.base_url}/core/items/{item_uuid}"

        r = self.request("GET", url, headers=self.headers)
        if r.status_code != 200:
            raise Exception(f"Metadata download failed: {r.status_code} {r.text}")

        metadata = r.json()["metadata"]
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2)

        print(f"Metadata saved: {output_path}")

    # ---------------------------
    # DOWNLOAD DATA
    # ---------------------------
    def export_bitstreams(self, item_uuid, output_folder):
        os.makedirs(output_folder, exist_ok=True)

        url = f"{self.base_url}/core/items/{item_uuid}/bitstreams"

        r = self.session.get(url, headers=self.headers)
        if r.status_code != 200:
            raise Exception(f"Cannot list bitstreams: {r.status_code} {r.text}")

        bitstreams = r.json()["_embedded"]["bitstreams"]

        for bs in bitstreams:
            name = bs["name"]
            download_link = bs["_links"]["content"]["href"]

            r2 = self.request("GET", download_link, headers=self.headers)
            if r2.status_code != 200:
                print(f"Failed to download {name}")
                continue

            with open(os.path.join(output_folder, name), "wb") as f:
                f.write(r2.content)

            print(f"Downloaded: {name}")

    # ---------------------------
    # CREATE ITEM
    # ---------------------------
    def create_item(self, collection_id, metadata):
        self.ensure_logged_in()
        url = f"{self.base_url}/submission/workspaceitems?owningCollection={collection_id}"
        payload = {
            "metadata": {},
            "inArchive": True,
            "discoverable": True,
            "withdrawn": False,
            "owningCollection": collection_id
            }

        r = self.request("POST",
                       url, 
                       headers={**self.headers, "Content-Type": "application/json"}, 
                       data=payload)
        if r.status_code not in (200, 201):
            raise Exception(f"Item creation failed: {r.status_code} {r.text}")
        workspaceID = r.json()["id"]

        payload = self.flatten_dspace_json(metadata)
        r2 = self.request("PATCH",
                          f"{self.base_url}/submission/workspaceitems/{workspaceID}",
                          headers={**self.headers, "Content-Type": "application/json"},
                          json=payload)
        wid = r.json()["id"]
        print(f"Metadata added. Workitem id =  {wid}")
        return wid
    # ---------------------------
    # CREATE ITEM
    # ---------------------------
    def get_item(self, workspace_item_id=None, uuid=None):
        if workspace_item_id:
            self.ensure_logged_in()
            url = f"{self.base_url}/submission/workspaceitems/{workspace_item_id}/item"  
        elif uuid:
            url = f"{self.base_url}/core/items/{uuid}"
        else:
            raise Exception("workspace id or uuid needs to be set")

        r = self.request("GET",
                       url, 
                       headers={**self.headers}
                       )
        return r.json()

    # ---------------------------
    # UPLOAD BITSTREAMS
    # ---------------------------
    def upload_file(self, workspace_item_id, filepath):
        self.ensure_logged_in()
        filename = os.path.basename(filepath)   

        url = f"{self.base_url}/submission/workspaceitems/{workspace_item_id}"  

        with open(filepath, "rb") as f:
            files = {
                "file": (filename, f, "application/octet-stream")
            }   

            r = self.request(
                "POST",
                url,
                headers={
                    **self.headers,  # do NOT set Content-Type manually
                },
                files=files
            )   

        if r.status_code not in (200, 201):
            raise Exception(f"Upload failed for {filename}: {r.status_code} {r.text}")  

        print(f"Uploaded: {filename} (workspace ID: {workspace_item_id})")

    def upload_folder(self, workspace_item_id, folder):
        files = glob.glob(os.path.join(folder, "*"))
        for file in files:
            if os.path.isfile(file):
                self.upload_file(workspace_item_id, file)


    # ---------------------------
    # DEPOSIT ITEM
    # ---------------------------
    def deposit_item(self, workspace_item_id):
        """
        Deposit a workspace item, turning it into an archived item.
        """
        self.ensure_logged_in()

        url = f"{self.base_url}/workflow/workflowitems"

        r = self.request(
            "POST",
            url,
            json={},
            headers={"Content-Type": "text/uri-list"},
            data = f"{self.base_url}/submission/workspaceitems/{workspace_item_id}"
        )

        if r.status_code not in (200, 201):
            raise Exception(f"Deposit failed: {r.status_code} {r.text}")

        print(f"Workspace item {workspace_item_id} deposited successfully")

    # ---------------------------
    # REQUEST WRAPPER
    # ---------------------------

    def request(self, method, url, params=None, json=None, data=None, files=None, headers=None):
        """Wrapper around requests.Session.request().

        method: "GET", "POST", "PUT", "PATCH", "DELETE"
        url: full URL
        params: dict for ?query parameters
        json: JSON body
        data: raw body (e.g. for form uploads)
        files: 
        headers: optional extra headers
        """

        # Always include our auth headers (JWT + XSRF)
        merged_headers = {**self.headers}
        if headers:
            merged_headers.update(headers)

        print(f"[DEBUG] ======= REQUEST ========  >>>")
        print(f"[DEBUG] {method} {url}")
        print(f"Headers: {merged_headers}")
        print(f"Params:  {params}")
        print(f"JSON:    {json}")
        print(f"Data:    {data}")
        print(f"Files:   {files}")
        print(f"Cookies: {self.session.cookies.get_dict()}")

        # Execute request through the same session (cookies preserved)
        response = self.session.request(
            method=method,
            url=url,
            params=params,
            json=json,
            data=data,
            files=files,
            headers=merged_headers,
        )

        print(f"[DEBUG] ======= RESPONSE =======  <<<")
        print(f"[DEBUG] Status: {response.status_code}")
        print(f"[DEBUG] Headers:   {response.headers}")
        print(f"[DEBUG] Body:   {response.text}")
        if response.headers.get("dspace-xsrf-token"):
            self.headers["X-XSRF-TOKEN"] = response.headers["dspace-xsrf-token"]
        token = response.headers.get("Authorization")
        if token:
            self.headers["Authorization"] = token
        return response

    def flatten_dspace_json(self, obj, path=""):
        """
        Recursively flatten a DSpace-style JSON into JSON Patch operations.
        """
        patch = []
        if isinstance(obj, dict):
            for k, v in obj.items():
                new_path = f"{path}/{k}" if path else f"/{k}"
                patch.extend(self.flatten_dspace_json(v, new_path))
        elif isinstance(obj, list):
            # DSpace metadata usually expects lists as values
            patch.append({
                "op": "add",
                "path": path,
                "value": obj
            })
        else:
            patch.append({
                "op": "add",
                "path": path,
                "value": obj
            })
        return patch



    def print_curl(self, method, url, headers=None, params=None, data=None, files=None):
      """
      Prints a curl command equivalent of a requests call.
      """
      cmd = f"curl -X {method.upper()}"

      # Headers
      if headers:
        for k, v in headers.items():
            cmd += f" -H '{k}: {v}'"

      # Data for POST
      if data:
        # If dict, convert to URL-encoded
        if isinstance(data, dict):
            from urllib.parse import urlencode
            data_str = urlencode(data)
        else:
            data_str = data
        cmd += f" --data '{data_str}'"

      # Files
      if files:
        for key, (filename, _) in files.items():
            cmd += f" -F '{key}=@{filename}'"

      # URL + query parameters
      if params:
        from urllib.parse import urlencode
        url += "?" + urlencode(params)

      cmd += f" '{url}'"
      print("request:\t", cmd, "\n")

    # ---------------------------
    # MAIN OPERATIONS
    # ---------------------------
    def get_operation(self, filters=[], collection_id=None):
      """
      Get items optionally filtered by metadata and collection.
      """

      items = self.search_items(metadata_filter=filters, collection_id=collection_id)
      content = items.get("_embedded", {}).get("searchResult", {}).get("_embedded", {}).get("objects", [])

      if not content:
        print("No items found.")
        return

      # Print nicely
      print(json.dumps(content, indent=2))


    def post_operation(self, collection_id, metadata_file, files_folder):
        with open(metadata_file, "r", encoding="utf-8") as f:
            metadata = json.load(f)

        wid = self.create_item(collection_id, metadata)
        self.upload_folder(wid, files_folder)
        item = self.get_item(wid)
        self.deposit_item(wid)
        print(f"Result: {item['uuid']}")
        return item["uuid"]


    def export_operation(self, filters, output_dir):
        """Find items by metadata - determine newest version - export metadata + files."""
        items = self.search_items(filter_key, filter_value)

        if not items:
            print("No items found.")
            return

        for item in items:
            uuid = item["uuid"]
            latest_uuid = self.get_latest_version(uuid)

            item_dir = os.path.join(output_dir, latest_uuid)
            os.makedirs(item_dir, exist_ok=True)

            # Export metadata
            self.export_metadata(latest_uuid, os.path.join(item_dir, "metadata.json"))

            # Export bitstreams
            self.export_bitstreams(latest_uuid, os.path.join(item_dir, "files"))

        print("Export completed.")



# ==================================================
# CLI INTERFACE
# ==================================================

def parse_filters(raw_filters):
    """Convert compact 'key:operator:value' strings into dict objects."""
    filters = []
    if not raw_filters:
        return filters

    for f in raw_filters:
        parts = f.split(":", 2)
        if len(parts) != 3:
            raise ValueError(
                f"Invalid filter format: '{f}'. Expected key:operator:value"
            )
        key, operator, value = parts
        filters.append({
            "key": key.strip(),
            "operator": operator.strip(),
            "value": value.strip(),
        })
    return filters

def main():
    parser = argparse.ArgumentParser(description="DSpace 7 REST client")

    parser.add_argument("--base_url", required=True)
    parser.add_argument("--username")
    parser.add_argument("--password")

    parser.add_argument("--mode", required=True, choices=["get", "post", "export"])

    # GET mode params
    parser.add_argument("--filter", action="append",
                    help='Filter in format "key:operator:value"')

    # POST mode params
    parser.add_argument("--collection")
    parser.add_argument("--metadata")
    parser.add_argument("--files")

    parser.add_argument("--output")


    args = parser.parse_args()

    client = DSpaceClient(args.base_url, args.username, args.password)

    if args.mode == "get":
      filters = parse_filters(args.filter)
      client.get_operation(
        filters=filters,
        collection_id=args.collection
       )
    elif args.mode == "post":
        if not args.collection or not args.metadata or not args.files:
            raise ValueError("For POST you must provide --collection, --metadata, --files")
        client.post_operation(args.collection, args.metadata, args.files)

    elif args.mode == "export":
        filters = parse_filters(args.filter)
        if not filters or not args.output:
            raise ValueError("For EXPORT you must provide --filter, --output")
        client.export_operation(filters=filters, output_dir=args.output)

if __name__ == "__main__":
    main()
