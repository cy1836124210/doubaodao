import sqlite3
c=sqlite3.connect(r'D:\aiwork\doubaoni\dev\lspd\m.db')
print('--- modules table schema ---')
print([r[1] for r in c.execute('pragma table_info(modules)')])
print('--- modules_state schema ---')
print([r[1] for r in c.execute('pragma table_info(modules_state)')])
print('--- all modules + state ---')
for r in c.execute('select m.module_pkg_name, m.apk_path, s.enabled from modules m left join modules_state s on s.module_pkg_name=m.module_pkg_name order by s.enabled desc'):
    print('  ', r)
