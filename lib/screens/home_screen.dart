import 'package:material_ui/material_ui.dart';

import '../shell/app_shell.dart';
import '../shell/tabs.dart';
import 'tab_page.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return TabPage(
      overline: russianDate(now),
      title: greeting(now),
      children: [
        EmptyCard(
          iconPath: AppTab.library.iconPath,
          title: 'Здесь будет «Слушаю сейчас»',
          text: 'Добавьте книгу, и с главной можно будет продолжить слушать с того же места.',
          action: 'Добавить книгу',
          onAction: () => TabSwitcher.of(context)(AppTab.add),
        ),
      ],
    );
  }
}

String greeting(DateTime t) => switch (t.hour) {
  >= 5 && < 12 => 'Доброе утро',
  >= 12 && < 18 => 'Добрый день',
  >= 18 && < 23 => 'Добрый вечер',
  _ => 'Доброй ночи',
};

String russianDate(DateTime t) {
  const days = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${days[t.weekday - 1]}, ${t.day} ${months[t.month - 1]}';
}
