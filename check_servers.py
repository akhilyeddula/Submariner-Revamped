import sqlite3

def check_servers():
    try:
        # Typical location for CoreData sqlite database in Mac app containers
        # But wait, it's easier to just search for the Submariner sqlite file in the app support dir
        import glob
        import os
        paths = glob.glob(os.path.expanduser('~/Library/Containers/*/Data/Library/Application Support/Submariner*/*.sqlite'))
        if not paths:
            paths = glob.glob(os.path.expanduser('~/Library/Application Support/Submariner*/*.sqlite'))
        
        for p in paths:
            print("Found DB:", p)
            conn = sqlite3.connect(p)
            c = conn.cursor()
            # The entity for SBServer is probably ZSERVER
            try:
                c.execute("SELECT ZURL FROM ZSERVER")
                for row in c.fetchall():
                    print("Server URL:", row[0])
            except Exception as e:
                print("Error querying ZSERVER:", e)
    except Exception as e:
        print("Error:", e)

check_servers()
