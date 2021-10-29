/// Biblioteca nativa de dart para execução em multiplos threads.
import 'dart:isolate';

/// Pacote de terceiros para consumo fácil de APIs.
///
/// Neste programa, utilizaremos duas APIs para demonstração de Threads.
/// A primeira, 'https://animechan.vercel.app/' é uma restful API que retorna
/// citações aleatórias de anime.
/// A segunda, 'https://agify.io/' é uma API que retorna uma previsão da idade
/// do personagem responsável pela citação através de seu primeiro nome.
import 'package:dio/dio.dart';

/// Função principal do programa.
void main(List<String> arguments) async {
  /// Inicializa uma porta de configuração para cada thread.
  final agifyThreadConfigPort = ReceivePort();
  final animeThread1ConfigPort = ReceivePort();
  final animeThread2ConfigPort = ReceivePort();

  /// Inicializa as threads através da porta de configuração.
  Isolate.spawn(agifyThread, agifyThreadConfigPort.sendPort);
  Isolate.spawn(animeThread, animeThread1ConfigPort.sendPort);
  Isolate.spawn(animeThread, animeThread2ConfigPort.sendPort);

  /// Recebe as portas para comunicação com as threads.
  ///
  /// Em dart as threads não compartilham memória, então o sistema de portas
  /// é utilizado para comunicação entre threads.
  final SendPort agifyThreadSendPort = await agifyThreadConfigPort.first;
  final SendPort animeThread1SendPort = await animeThread1ConfigPort.first;
  final SendPort animeThread2SendPort = await animeThread2ConfigPort.first;

  /// Envia um número de identificação para as animeThreads.
  animeThread1SendPort.send(1);
  animeThread2SendPort.send(2);

  /// Declara as portas para recepção de mensagens de retorno das threads.
  ///
  /// O sistema de portas é unidirecional, portanto é necessário declarar uma
  /// porta para envio de mensagens a partir da thread principal, e uma porta
  /// para recepção de mensagens de retorno para cada thread auxiliar.
  final agifyThreadReceivePort = ReceivePort();
  final animeThread1ReceivePort = ReceivePort();
  final animeThread2ReceivePort = ReceivePort();

  /// Informa para as threads auxiliares qual endereço devem utilizar para envio
  /// de mensagens para a thread principal.
  agifyThreadSendPort.send(agifyThreadReceivePort.sendPort);
  animeThread1SendPort.send({
    'agifyThreadSP': agifyThreadSendPort,
    'mainThreadSP': animeThread1ReceivePort.sendPort
  });
  animeThread2SendPort.send({
    'agifyThreadSP': agifyThreadSendPort,
    'mainThreadSP': animeThread2ReceivePort.sendPort
  });

  /// Informa para as animeThreads que sua inicialização foi concluída.
  animeThread1SendPort.send('initialization completed');
  animeThread2SendPort.send('initialization completed');

  /// Contador para controlar quando o processo principal pode ser encerrado.
  ///
  /// Cada animeThread envia cinco personagens para a agifyThread, que realiza
  /// dois retornos por personagem, um avisando que a execução da thread começou
  /// e outro com o resultado, então o processo principal precisa esperar que o
  /// contador atinja 20 para encerrar.
  var receivedAges = 0;

  /// Recebe as mensagens de retorno da agifyThread.
  agifyThreadReceivePort.listen((data) {
    receivedAges++;

    print(data);

    /// Quando o contador atingir 20, encerra todas as threads.
    if (receivedAges == 20) {
      agifyThreadReceivePort.close();
      animeThread1ReceivePort.close();
      animeThread2ReceivePort.close();

      agifyThreadSendPort.send('shutdown');

      return;
    }
  });

  /// Recebe as mensagens de retorno das animeThreads.
  animeThread1ReceivePort.listen((data) => print(data));
  animeThread2ReceivePort.listen((data) => print(data));
}

/// Thread que consome a API de citações de anime.
///
/// Esta thread se comunica com a thread principal e também com a agifyThread.
void animeThread(SendPort sendPort) async {
  /// Permite que esta thread receba mensagens de outras.
  final port = ReceivePort();

  /// Informa as outras threads o caminho para conversar com esta thread.
  sendPort.send(port.sendPort);

  /// Inicializa o cliente para leitura da API.
  final dio = Dio();

  /// Receberá o número identificador da thread.
  late final int threadNumber;

  /// Receberá o canal de interação com a thread do agify.
  late final SendPort agifyThreadSP;

  /// Receberá o canal de interação com a thread principal.
  late final SendPort mainThreadSP;

  /// Entra no loop de execução da thread.
  ///
  /// Irá consultar a API de citações aleatórias de anime 5 vezes, imprimindo os
  /// resultados obtidos e enviando o nome do personagem para a thread do agify.
  ///
  /// Após isto, automaticamente encerra a thread.
  await for (var msg in port) {
    if (msg is int) {
      threadNumber = msg;
    } else if (msg is Map<String, SendPort>) {
      mainThreadSP = msg['mainThreadSP']!;
      agifyThreadSP = msg['agifyThreadSP']!;
    } else if (msg is String) {
      for (var i = 0; i < 5; i++) {
        /// Recebe uma citação aleatória da API.
        dio.get('https://animechan.vercel.app/api/random').then((response) {
          final anime = response.data?['anime'] ?? '';
          final character = response.data?['character'] ?? '';
          final quote = response.data?['quote'] ?? '';

          /// Envia as informações sobre a citação pega para a thread principal.
          mainThreadSP.send(
            'animeThread$threadNumber:'
            '\n\tAnime: $anime'
            '\n\tPersonagem: $character'
            '\n\tCitação: $quote',
          );

          /// Envia o nome do personagem dono da citação para a agifyThread.
          agifyThreadSP.send(character);
        });
      }

      /// Encerra a comunicação com a thread, que será concluída logo após.
      port.close();
    }
  }
}

/// Thread que consome a API de previsão de idade.
///
/// Esta thread recebe nomes de personagens e envia à thread principal a idade
/// prevista pelo nome.
///
/// Como esta API tem uma resposta mais lenta que a outra, a agifyThread também
/// envia uma mensagem para a thread principal informando que a execução foi
/// iniciada.
void agifyThread(SendPort sendPort) async {
  /// Permite que esta thread receba mensagens de outras.
  final port = ReceivePort();

  /// Informa as outras threads o caminho para conversar com esta thread.
  sendPort.send(port.sendPort);

  /// Inicializa o cliente para leitura de API.
  final dio = Dio();

  /// Receberá o canal de interação com a thread principal.
  late final SendPort mainThreadSP;

  /// Espera por mensagens.
  ///
  /// Quando uma mensagem é recebida irá consultar a API de definição de idade
  /// através do primeiro nome e informar o resultado.
  await for (var msg in port) {
    if (msg is SendPort) {
      mainThreadSP = msg;
    } else if (msg == 'shutdown') {
      /// Encerra a thread caso a mensagem seja 'shutdown'.
      port.close();
    } else {
      /// Envia a primeira mensagem, para evidenciar a execução paralela da
      /// thread.
      mainThreadSP.send('Entrou no agifyThread');

      final firstName = msg.split(' ').first;

      /// Recebe a idade prevista da API.
      dio.get('https://api.agify.io/?name=$firstName').then((response) {
        /// Envia a idade prevista para a thread principal.
        mainThreadSP.send(
          'agified character: $msg'
          '\n\tage: ${response.data?['age'] ?? 0}',
        );
      });
    }
  }
}
