import { Provider } from '@angular/core';
import { TjBackend } from './backend.interface';
import { HttpBackendService } from './http-backend.service';

export const backendProvider: Provider = {
  provide: TjBackend,
  useClass: HttpBackendService,
};
