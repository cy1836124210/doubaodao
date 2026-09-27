import sqlite3
c=sqlite3.connect(r'D:\aiwork\doubaoni\dev\lspd\m.db')
print('--- scope for com.islandbridge ---')
for r in c.execute("select * from scope where module_pkg_name='com.islandbridge'"):
    print('  ',r)
print('--- scope for astraflow / null scope (all) ---')
for r in c.execute("select distinct module_pkg_name, app_pkg_name, user_id from scope order by module_pkg_name"):
    print('  ',r)
print('--- modules ---')
for r in c.execute("select module_pkg_name, apk_path, enabled from modules"):
    print('  ',r)
